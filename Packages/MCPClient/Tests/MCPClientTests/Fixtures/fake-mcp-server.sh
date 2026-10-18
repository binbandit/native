#!/bin/sh
# A minimal stdio MCP server for tests: answers initialize, two pages of tools/list and tools/call.
# "crash" exits with status 3 after logging; "hang" reads and never answers; "clean" leaves out the
# stray stdout line, which strict clients (Codex) treat as a broken server.
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
      [ "$mode" = "clean" ] || echo "this line is not JSON-RPC"
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
    *'"method":"tools/call"'*)
      case "$line" in
        *'"name":"search"'*)
          printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"1 match"}],"structuredContent":{"matches":["thing"]}}}\n' "$id"
          ;;
        *)
          printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"Nothing to delete."}],"isError":true}}\n' "$id"
          ;;
      esac
      ;;
    *'"method":"notifications/'*) ;;
    *'"method":'*)
      [ -n "$id" ] && printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Method not found"}}\n' "$id"
      ;;
  esac
done
