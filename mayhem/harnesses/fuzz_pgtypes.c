/*
 * ecpg's libpgtypes text parsers: numeric, date, timestamp, interval.
 * Byte 0 selects the type.
 */
#include "postgres_fe.h"

#include "pgtypes_date.h"
#include "pgtypes_interval.h"
#include "pgtypes_numeric.h"
#include "pgtypes_timestamp.h"

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	int			kind;
	char	   *str;
	char	   *end = NULL;
	char	   *txt;

	if (size < 1)
		return -1;
	kind = data[0] & 3;
	data++;
	size--;

	str = malloc(size + 1);
	if (str == NULL)
		return 0;
	memcpy(str, data, size);
	str[size] = '\0';

	switch (kind)
	{
		case 0:
			{
				numeric    *n = PGTYPESnumeric_from_asc(str, &end);

				if (n != NULL)
				{
					txt = PGTYPESnumeric_to_asc(n, -1);
					free(txt);
					PGTYPESnumeric_free(n);
				}
				break;
			}
		case 1:
			{
				date		d = PGTYPESdate_from_asc(str, &end);

				txt = PGTYPESdate_to_asc(d);
				free(txt);
				break;
			}
		case 2:
			{
				timestamp	t = PGTYPEStimestamp_from_asc(str, &end);

				txt = PGTYPEStimestamp_to_asc(t);
				free(txt);
				break;
			}
		default:
			{
				interval   *iv = PGTYPESinterval_from_asc(str, &end);

				if (iv != NULL)
				{
					txt = PGTYPESinterval_to_asc(iv);
					free(txt);
					free(iv);
				}
				break;
			}
	}
	free(str);
	return 0;
}
