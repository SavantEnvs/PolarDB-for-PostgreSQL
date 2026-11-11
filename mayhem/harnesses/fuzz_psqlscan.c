/*
 * fe_utils/psqlscan.l: psql's lexer, as used by psql and pgbench to split
 * SQL text into statements.  Byte 0 selects client encoding and
 * standard_conforming_strings.
 */
#include "postgres_fe.h"

#include "fe_utils/psqlscan.h"
#include "mb/pg_wchar.h"
#include "pqexpbuffer.h"

static char *
get_variable(const char *varname, PsqlScanQuoteType quote, void *passthrough)
{
	if (varname[0] == 'x')
		return NULL;
	return strdup(quote == PQUOTE_PLAIN ? "v" : "'v'");
}

static const PsqlScanCallbacks callbacks = {get_variable};

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	PsqlScanState state;
	PQExpBufferData buf;
	promptStatus_t prompt;
	PsqlScanResult res;
	int			enc;
	bool		std_strings;
	char	   *line;

	if (size < 1)
		return -1;
	enc = (data[0] >> 1) % _PG_LAST_ENCODING_;
	std_strings = (data[0] & 1) != 0;
	data++;
	size--;

	line = malloc(size + 1);
	if (line == NULL)
		return 0;
	memcpy(line, data, size);
	line[size] = '\0';

	state = psql_scan_create(&callbacks);
	initPQExpBuffer(&buf);
	psql_scan_setup(state, line, (int) size, enc, std_strings);
	do
	{
		resetPQExpBuffer(&buf);
		res = psql_scan(state, &buf, &prompt);
	} while (res == PSCAN_SEMICOLON);
	(void) psql_scan_in_quote(state);
	psql_scan_finish(state);
	psql_scan_destroy(state);
	termPQExpBuffer(&buf);
	free(line);
	return 0;
}
