#!/usr/bin/env bash
#
# mayhem/test.sh — RUN PolarDB's own libpq URI/conninfo and incremental-JSON tests (built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


T="$SRC/mayhem/build-test"
URI="$T/src/interfaces/libpq/test/libpq_uri_regress"
JSONP="$T/src/test/modules/test_json_parser/test_json_parser_incremental"
export LD_LIBRARY_PATH="$T/src/interfaces/libpq${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
for v in $(env | sed -n 's/^\(PG[A-Z]*\)=.*/\1/p'); do unset "$v"; done

for exe in "$URI" "$JSONP"; do
  [ -x "$exe" ] || { echo "missing test binary $exe (mayhem/build.sh should have built it)" >&2; emit_ctrf "polardb-kat" 0 1; exit 1; }
done

passed=0 failed=0

# libpq URI / conninfo parsing: input, expected stdout, expected stderr — the cases of
# src/interfaces/libpq/t/001_uri.pl.
check_uri() {
  local in="$1" want_out="$2" want_err="$3" out err
  out=$("$URI" "$in" 2>/tmp/uri.err); err=$(cat /tmp/uri.err)
  if [ "$out" == "$want_out" ] && [ "$err" == "$want_err" ]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); echo "FAIL uri: $in" >&2; echo "  stdout: got [$out] want [$want_out]" >&2; echo "  stderr: got [$err] want [$want_err]" >&2
  fi
}
check_uri 'postgresql://uri-user:secret@host:12345/db' "user='uri-user' password='secret' dbname='db' host='host' port='12345' (inet)" ''
check_uri 'postgresql://uri-user@host/db' "user='uri-user' dbname='db' host='host' (inet)" ''
check_uri 'postgresql://host:12345/' "host='host' port='12345' (inet)" ''
check_uri 'postgresql://uri-user@' "user='uri-user' (local)" ''
check_uri 'postgresql://' '(local)' ''
check_uri 'postgresql://?hostaddr=127.0.0.1' "hostaddr='127.0.0.1' (inet)" ''
check_uri 'postgresql://%68ost/' "host='host' (inet)" ''
check_uri 'postgresql://host/db?u%73er=someotheruser&port=12345' "user='someotheruser' dbname='db' host='host' port='12345' (inet)" ''
check_uri 'postgresql://[2001:db8::1234]/' "host='2001:db8::1234' (inet)" ''
check_uri 'postgres:///db' "dbname='db' (local)" ''
check_uri 'postgres://?host=/path/to/socket/dir' "host='/path/to/socket/dir' (local)" ''
check_uri 'postgres://otheruser@:12345/db?host=/path/to/socket' "user='otheruser' dbname='db' host='/path/to/socket' port='12345' (local)" ''
check_uri 'postgresql://host?uzer=' '' 'libpq_uri_regress: invalid URI query parameter: "uzer"'
check_uri 'postgres://[::1' '' 'libpq_uri_regress: end of string reached when looking for matching "]" in IPv6 host address in URI: "postgres://[::1"'
check_uri 'postgres://[]' '' 'libpq_uri_regress: IPv6 host address may not be empty in URI: "postgres://[]"'
check_uri 'postgresql://host?key=key=value' '' 'libpq_uri_regress: extra key/value separator "=" in URI query parameter: "key"'
check_uri 'postgresql://a%00b' '' 'libpq_uri_regress: forbidden value %00 in percent-encoded value: "a%00b"'
check_uri 'postgres://@host' "host='host' (inet)" ''
check_uri 'host=localhost port=5433 dbname=mydb user=bob' "user='bob' dbname='mydb' host='localhost' port='5433' (inet)" ''

# Incremental JSON parser with semantic callbacks: output must equal upstream's golden tiny.out,
# at every chunk size.
J="$SRC/src/test/modules/test_json_parser"
for chunk in 1 7 60 6000; do
  "$JSONP" -s -c "$chunk" "$J/tiny.json" > /tmp/tiny.got 2>&1
  if cmp -s /tmp/tiny.got "$J/tiny.out"; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); echo "FAIL json: tiny.json at chunk size $chunk differs from tiny.out" >&2
  fi
done
printf '{"a":[1,2,{"b":null}],"c":"\\u00e9"}' > /tmp/kat.json
out=$("$JSONP" -s /tmp/kat.json 2>&1)
want=$(printf '{\n"a": [\n1,\n2,\n{\n"b": null\n}\n\n]\n,\n"c": "é"\n}')
if [ "$out" == "$want" ]; then passed=$((passed+1)); else failed=$((failed+1)); echo "FAIL json KAT: got [$out]" >&2; fi
if "$JSONP" /tmp/kat.json >/dev/null 2>&1; then passed=$((passed+1)); else failed=$((failed+1)); echo "FAIL json: valid doc rejected" >&2; fi
printf '{"a":[1,2' > /tmp/bad.json
if "$JSONP" /tmp/bad.json >/dev/null 2>&1; then failed=$((failed+1)); echo "FAIL json: truncated doc accepted" >&2; else passed=$((passed+1)); fi

emit_ctrf "polardb-kat" "$passed" "$failed"
