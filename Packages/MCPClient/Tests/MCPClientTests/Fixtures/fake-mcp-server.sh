#!/bin/sh
# A minimal stdio MCP server for tests: answers initialize and two pages of tools/list.
# "crash" exits with status 3 after logging; "hang" reads and never answers.
mode="$1"
echo "fake server starting in ${mode:-normal} mode" >&2
if [ "$mode" = "crash" ]; then
  echo "error: missing API key" >&2
  exit 3
fi
while IFS= read -r line; do
  [ "$mode" = "hang" ] && continue
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*)
      echo "this line is not JSON-RPC"
      printf '{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info","data":"hello"}}\n'
      printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"fake","title":"Fake Server","version":"1.2.3"},"instructions":"Use the fake tools."}}\n' "$id"
      ;;
    *'"method":"tools/list"'*)
      case "$line" in
        *'"cursor"'*)
          printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[{"name":"delete","description":"Deletes a thing.","inputSchema":{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]},"annotations":{"destructiveHint":true}}]}}\n' "$id"
          ;;
        *)
          printf '{"jsonrpc":"2.0","id":99,"method":"roots/list"}\n'
          printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[{"name":"search","title":"Search","description":"Finds things.","inputSchema":{"type":"object","properties":{"limit":{"type":"number"},"query":{"type":"string"}},"required":["query"]},"annotations":{"readOnlyHint":true}}],"nextCursor":"page-2"}}\n' "$id"
          ;;
      esac
      ;;
  esac
done
