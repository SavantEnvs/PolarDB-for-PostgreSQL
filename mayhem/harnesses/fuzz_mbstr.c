/*
 * common/wchar.c: multibyte verification for every encoding, then (on
 * verified strings, the precondition of the converters) mb<->wchar conversion.
 * Byte 0 selects the encoding.
 */
#include "postgres_fe.h"

#include "mb/pg_wchar.h"

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	int			enc;
	const char *s;
	int			len;
	int			vlen;

	if (size < 1)
		return -1;
	enc = data[0] % _PG_LAST_ENCODING_;
	s = (const char *) data + 1;
	len = (int) size - 1;

	vlen = pg_encoding_verifymbstr(enc, s, len);
	if (vlen == len && len > 0)
	{
		pg_wchar   *w = malloc(((size_t) len + 1) * sizeof(pg_wchar));
		unsigned char *back = malloc((size_t) len * 4 + 8);

		if (w != NULL && back != NULL)
		{
			const char *p = s;

			/* client-only encodings have no wchar converters */
			if (pg_wchar_table[enc].mb2wchar_with_len != NULL &&
				pg_wchar_table[enc].wchar2mb_with_len != NULL)
			{
				int			nw = pg_wchar_table[enc].mb2wchar_with_len((const unsigned char *) s, w, len);

				if (nw >= 0)
					(void) pg_wchar_table[enc].wchar2mb_with_len(w, back, nw);
			}
			while (p < s + len)
			{
				int			l = pg_encoding_mblen(enc, p);

				(void) pg_encoding_dsplen(enc, p);
				if (l <= 0)
					break;
				p += l;
			}
		}
		free(w);
		free(back);
	}
	return 0;
}
