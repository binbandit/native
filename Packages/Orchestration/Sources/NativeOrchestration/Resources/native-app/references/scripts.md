# Gather results with JavaScript

When the sandboxed script runtime is available, `scripts/native run_script` runs an ES module body
with top-level await. It has no filesystem, network, imports, require or process access. Print output
with `text(value)` or `console.log(value)`. Tool failures reject their promises.

```sh
scripts/native run_script '{"code":"const result = await tools.list_tasks({}); text(result);","timeout_seconds":60}'
```

Required: `code` (string). Optional: `inputs` (object of strings accessible as `inputs.<name>`) and
`timeout_seconds` (integer 1-240, default 60). Returns `output`, `tool_calls` and optional `failure`
with kind, message, line and column. The command exits nonzero if the script fails.

Bound Native tools: `list_agents({})`, `list_tasks({})`, `get_task({task_id})`, and
`wait_for_task({task_id, timeout_seconds?})`. Their results are the same as the CLI's JSON results.
These Native bindings are read-only. For other MCP servers the user has connected in script mode,
use `tools.search({query, limit?})` to get declarations on demand, then call those tools in a later
script. Those servers retain their policy and permission checks. This command needs the Native app
running and its script runtime enabled; use individual task commands when it is unavailable.
