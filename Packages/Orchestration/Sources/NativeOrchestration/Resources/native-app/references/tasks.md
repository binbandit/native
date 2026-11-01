# Tasks and messages

Use the `native` executable beside this skill, under `scripts/`. Examples below assume its path
is in `$native`. Agent IDs come from `list_agents`; task IDs come from `start_task` or `list_tasks`.

| Action | Command |
| --- | --- |
| Available agents | `"$native" list_agents` |
| Start work | `"$native" start_task '{"agent":"claude-code","prompt":"Review the parser. Report bugs only.","title":"Review parser"}'` |
| Related tasks | `"$native" list_tasks` |
| Latest status and reply | `"$native" get_task '{"task_id":"task-id"}'` |
| Wait for a reply | `"$native" wait_for_task '{"task_id":"task-id","timeout_seconds":60}'` |
| Send instructions or a message | `"$native" send_message '{"to":"parent","message":"The parser check passed."}'` |
| Stop your child's current turn | `"$native" cancel_task '{"task_id":"task-id"}'` |

Delegate work that benefits from another task or model. The child shares your project directory but
has no conversation context: give it a self-contained goal, files, constraints and expected report.
Avoid overlapping edits. The user sees it as a subagent and approves its tool calls.

`start_task` requires `agent` and `prompt`; `title` is optional. It returns immediately with
`task_id`. `wait_for_task` waits up to 120 seconds by default, between 1 and 240 seconds. A status
of `running` means call again or do other work; `needs_approval` means the user must approve in
Native. `get_task` checks without waiting. Replies can be partial while a task runs.

Read, wait and message accept every task `list_tasks` shows, including `"parent"`. Cancellation
only accepts your own children. Messages steer a running turn, queue for the next one, or start a
new turn if the recipient is idle. They do not wait for an answer. A stopped child stays open and
can receive a follow-up. Coordinator tasks keep their assigned-task scope and read-only limits.

`start_task` also accepts `model`, `effort`, `permissions`, and `checkout`. Use exact advertised
values from `list_agents` (optional `search` and `limit`). Settings there are last observations;
an empty catalog means unknown. The new session validates them before its first prompt. Permissions
inherit a known equivalent or stricter mode by default. Explicit unsupported modes or escalation
are refused; ask the user to change the parent's permissions in Native if broader access is needed.
`checkout` selects an existing absolute directory on the executing host. It does not create a
worktree or copy uncommitted changes. No model or effort is silently substituted.

Host task tools also advertise `durable_creation_and_completion` in `list_agents`. On that runtime:

- Supply a `creation_key` (1 to 128 bytes, without control characters), keep it stable across retries, and send the same request. It is scoped to your parent task. Concurrent calls and retries after restart return the same creation receipt. A changed request is refused. If creation was interrupted before admission, Native refuses an ambiguous retry instead of creating another child.
- Completion delivery defaults to on. After you finish your turn, the host sends the original result, including after disconnects or host restarts. `notify_on_completion: false` opts out. A terminal `wait_for_task` or `get_task` consumes a pending wake when you have already read the result.
- `original_result` is immutable and bounded (32,768 reply characters plus a truncation notice). The ordinary `reply` is the latest turn, including follow-ups. Full text remains in the child transcript.
- A task stays running while its descendants or their completion delivery are outstanding. Stop and `cancel_task` cancel the owned subtree and durably suppress its completion wakes. An explicit later user message can resume work without reviving old wakes.

App-owned fallback tools refuse explicit durable creation or completion options. Use the host tools for these guarantees.
