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
