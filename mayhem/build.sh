#!/usr/bin/env bash
#
# mayhem/build.sh — build PolarDB's frontend libraries (libpq, libpgcommon, libpgport, libpgfeutils,
# libpgtypes) with sanitizers + SanCov and link each fuzz harness against them; also build the
# upstream test programs with NORMAL flags for mayhem/test.sh.
#
# Both builds are out of tree (VPATH) under mayhem/build-fuzz and mayhem/build-test, which
# mayhem/.gitignore covers. Re-runnable and offline: configure runs once per build dir.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC=${SRC:-/mayhem}
cd "$SRC"
unset CFLAGS CPPFLAGS LDFLAGS

CONFIGURE_OPTS=(--without-readline --without-zlib --without-icu --without-openssl --without-ldap
                --without-libxml --without-libxslt --without-gssapi --without-pam --without-systemd
                --without-selinux --without-llvm --without-lz4 --without-zstd)

# ---------------------------------------------------------------------------------------------
# 1) Sanitized + SanCov-instrumented libraries.
# ---------------------------------------------------------------------------------------------
B="$SRC/mayhem/build-fuzz"
mkdir -p "$B"
if [ ! -f "$B/src/include/pg_config.h" ]; then
  # Configure's own probes run unsanitized; the sanitizer flags go in via COPT at make time.
  (cd "$B" && ../../configure CC="$CC" CFLAGS="-O1" "${CONFIGURE_OPTS[@]}" >/dev/null)
fi
# UBSan checks relaxed for PostgreSQL's idioms: alignment (packed on-disk/wire structs read through
# casts), pointer-overflow (NULL+0), function (generic callback casts). ASan and the rest of UBSan halt.
COPT="$SANITIZER_FLAGS -fno-sanitize=alignment,pointer-overflow,function $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
make -s -C "$B/src/backend" generated-headers
make -s -C "$B/src/port" -j"$MAYHEM_JOBS" COPT="$COPT" libpgport.a libpgport_shlib.a
make -s -C "$B/src/common" -j"$MAYHEM_JOBS" COPT="$COPT" libpgcommon.a libpgcommon_shlib.a
make -s -C "$B/src/interfaces/libpq" -j"$MAYHEM_JOBS" COPT="$COPT" libpq.a
make -s -C "$B/src/fe_utils" -j"$MAYHEM_JOBS" COPT="$COPT" libpgfeutils.a
make -s -C "$B/src/interfaces/ecpg/pgtypeslib" -j"$MAYHEM_JOBS" COPT="$COPT" libpgtypes.a

# ---------------------------------------------------------------------------------------------
# 2) Harnesses: each linked twice (libFuzzer, and the run-once standalone reproducer).
# ---------------------------------------------------------------------------------------------
INC=(-I"$B/src/include" -I"$SRC/src/include" -I"$SRC/src/interfaces/libpq"
     -I"$SRC/src/interfaces/ecpg/include" -I"$B/src/interfaces/ecpg/include" -D_GNU_SOURCE)
LIBS=("$B/src/fe_utils/libpgfeutils.a" "$B/src/interfaces/libpq/libpq.a"
      "$B/src/interfaces/ecpg/pgtypeslib/libpgtypes.a"
      "$B/src/common/libpgcommon.a" "$B/src/port/libpgport.a" -lm -lpthread)
# libpq's objects are built to be linked into libpq.so, so they expect the *_shlib flavour of
# libpgcommon/libpgport (encoding functions without the _private suffix).
LIBS_LIBPQ=("$B/src/interfaces/libpq/libpq.a" "$B/src/common/libpgcommon_shlib.a"
            "$B/src/port/libpgport_shlib.a" -lm -lpthread)

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/harnesses/shlib_shim.c" -o "$B/shlib_shim.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"

for h in conninfo json pglz mbstr unicode psqlscan pgtypes; do
  src="$SRC/mayhem/harnesses/fuzz_$h.c"
  if [ "$h" = conninfo ]; then libs=("${LIBS_LIBPQ[@]}"); else libs=("$B/shlib_shim.o" "${LIBS[@]}"); fi
  $CC -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link "${INC[@]}" -c "$src" -o "$B/fuzz_$h.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/fuzz_$h.o" "$B/lsan_off.o" \
      "${libs[@]}" -o "$SRC/fuzz_$h"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$B/standalone_main.o" "$B/fuzz_$h.o" "$B/lsan_off.o" \
      "${libs[@]}" -o "$SRC/fuzz_$h-standalone"
done

# ---------------------------------------------------------------------------------------------
# 3) Upstream test programs with the project's NORMAL flags (no sanitizers) for mayhem/test.sh.
# ---------------------------------------------------------------------------------------------
T="$SRC/mayhem/build-test"
mkdir -p "$T"
if [ ! -f "$T/src/include/pg_config.h" ]; then
  (cd "$T" && ../../configure CC="$CC" CFLAGS="$COVERAGE_FLAGS" "${CONFIGURE_OPTS[@]}" >/dev/null)
fi
make -s -C "$T/src/backend" generated-headers
make -s -C "$T/src/port" -j"$MAYHEM_JOBS"
make -s -C "$T/src/common" -j"$MAYHEM_JOBS"
make -s -C "$T/src/interfaces/libpq" -j"$MAYHEM_JOBS"
make -s -C "$T/src/interfaces/libpq/test" -j"$MAYHEM_JOBS"
make -s -C "$T/src/test/modules/test_json_parser" -j"$MAYHEM_JOBS" test_json_parser_incremental
