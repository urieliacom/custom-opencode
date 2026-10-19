.output /dev/null
LOAD duckdb_mcp;
PRAGMA mcp_server_start('stdio');
