/*
 * common/saslprep.c and common/unicode_norm.c on arbitrary UTF-8.
 * Byte 0 selects the normalization form.
 */
#include "postgres_fe.h"

#include "common/saslprep.h"
#include "common/unicode_norm.h"
#include "mb/pg_wchar.h"

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	UnicodeNormalizationForm form;
	char	   *str;
	char	   *out = NULL;
	pg_wchar   *w;
	pg_wchar   *norm;

	if (size < 1)
		return -1;
	form = (UnicodeNormalizationForm) (data[0] & 3);
	data++;
	size--;

	str = malloc(size + 1);
	if (str == NULL)
		return 0;
	memcpy(str, data, size);
	str[size] = '\0';

	if (pg_encoding_verifymbstr(PG_UTF8, str, (int) size) != (int) size ||
		memchr(str, '\0', size) != NULL)
	{
		free(str);
		return -1;
	}

	if (pg_saslprep(str, &out) == SASLPREP_SUCCESS)
		free(out);

	w = malloc((size + 1) * sizeof(pg_wchar));
	if (w != NULL)
	{
		int			n = pg_wchar_table[PG_UTF8].mb2wchar_with_len((const unsigned char *) str, w, (int) size);

		w[n] = 0;
		norm = unicode_normalize(form, w);
		free(norm);
		free(w);
	}
	free(str);
	return 0;
}
