/*
 * common/pg_lzcompress.c: pglz_decompress() of arbitrary compressed bytes
 * (bytes 0-1 give the claimed raw size), plus a compress/decompress round trip.
 */
#include "postgres_fe.h"

#include "common/pg_lzcompress.h"

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	int32		rawsize;
	char	   *dest;
	char	   *comp;
	char	   *back;
	int32		clen;

	if (size < 2)
		return -1;
	rawsize = data[0] | (data[1] << 8);
	data += 2;
	size -= 2;

	dest = malloc(rawsize + 1);
	if (dest == NULL)
		return 0;
	(void) pglz_decompress((const char *) data, (int32) size, dest, rawsize, true);
	(void) pglz_decompress((const char *) data, (int32) size, dest, rawsize, false);
	free(dest);

	comp = malloc(PGLZ_MAX_OUTPUT((int32) size));
	if (comp == NULL)
		return 0;
	clen = pglz_compress((const char *) data, (int32) size, comp,
						 PGLZ_strategy_always);
	if (clen >= 0)
	{
		back = malloc(size + 1);
		if (back != NULL)
		{
			int32		n = pglz_decompress(comp, clen, back, (int32) size, true);

			if (n != (int32) size || memcmp(back, data, size) != 0)
				abort();
			free(back);
		}
	}
	free(comp);
	return 0;
}
