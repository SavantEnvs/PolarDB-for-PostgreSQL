/* libpq connection-string / postgresql:// URI parser. */
#include "postgres_fe.h"

#include "libpq-fe.h"

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char	   *conninfo = malloc(size + 1);
	char	   *errmsg = NULL;
	PQconninfoOption *opts;

	if (conninfo == NULL)
		return 0;
	memcpy(conninfo, data, size);
	conninfo[size] = '\0';

	opts = PQconninfoParse(conninfo, &errmsg);
	if (opts != NULL)
		PQconninfoFree(opts);
	if (errmsg != NULL)
		PQfreemem(errmsg);
	free(conninfo);
	return 0;
}
