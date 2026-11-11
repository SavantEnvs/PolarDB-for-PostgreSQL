/* libpq.a objects expect the libpq.so flavour of libpgcommon's encoding names; map them onto the
 * frontend libpgcommon.a ones so psqlscan and libpq's PQmblen* link against one libpgcommon. */
extern int pg_char_to_encoding_private(const char *name);
extern const char *pg_encoding_to_char_private(int encoding);

int pg_char_to_encoding(const char *name) { return pg_char_to_encoding_private(name); }
const char *pg_encoding_to_char(int encoding) { return pg_encoding_to_char_private(encoding); }
