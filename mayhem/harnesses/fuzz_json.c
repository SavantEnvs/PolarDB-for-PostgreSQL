/*
 * common/jsonapi.c: the recursive-descent parser and the incremental
 * (chunked) parser.  Byte 0 selects the mode; the rest is the document.
 */
#include "postgres_fe.h"

#include "common/jsonapi.h"
#include "mb/pg_wchar.h"

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	JsonLexContext *lex;
	JsonParseErrorType rc;
	bool		need_escapes;
	bool		incremental;
	size_t		chunk;

	if (size < 2)
		return -1;
	incremental = (data[0] & 1) != 0;
	need_escapes = (data[0] & 2) != 0;
	chunk = (size_t) (data[1] & 0x3f) + 1;
	data += 2;
	size -= 2;

	if (!incremental)
	{
		lex = makeJsonLexContextCstringLen(NULL, (const char *) data, size,
										   PG_UTF8, need_escapes);
		rc = pg_parse_json(lex, &nullSemAction);
	}
	else
	{
		size_t		off = 0;

		lex = makeJsonLexContextIncremental(NULL, PG_UTF8, need_escapes);
		rc = JSON_SUCCESS;
		do
		{
			size_t		n = size - off < chunk ? size - off : chunk;
			bool		last = (off + n == size);

			rc = pg_parse_json_incremental(lex, &nullSemAction,
										   (const char *) data + off, n, last);
			off += n;
		} while (rc == JSON_INCOMPLETE);
	}

	if (rc != JSON_SUCCESS)
		(void) json_errdetail(rc, lex);
	freeJsonLexContext(lex);
	return 0;
}
