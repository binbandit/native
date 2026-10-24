# Coordinator tasks (Labs, slice 1)

A coordinator aligns tasks the user already has. It starts in the project's folder without
creating a branch or worktree. Settings > Labs > Coordinator tasks defaults off. File > New
Coordinator Task opens a picker for an agent and active tasks in the current project. The user
can change assignments later with File > Edit Assigned Tasks. No new keyboard shortcut is reserved.

## Boundaries

This slice uses the local durable host and its existing orchestration MCP server. It adds no
listener, endpoint, download or model call. The Orchestration plugin and managed MCP policy must
permit Native's tools. An unavailable host or unsupported read-only agent fails creation with
an explanation. Remote-host coordinators and app-only agents are deferred.

Creation selects an advertised read-only permission level before publishing the task. It never
silently falls back to permission to edit. This is the agent's own sandbox, not a new filesystem
sandbox. The user can subsequently change autonomy with the existing controls. Coordination
messages deliberately ask other tasks to work, even while the coordinator's files are read-only.

The trusted client validates project membership and opens existing local tasks from the same project, including worktrees. The host accepts assignment changes only from a local client and independently checks task type, self-assignment and exclusive ownership.
The host stores the coordinator and its assigned task IDs together, using lasting agent task identities, with the coordinator also bound to its durable host identity.
An agent cannot change assignments. A task has at most one coordinator; coordinators cannot be
assigned to other coordinators. Removing an assignment takes effect on the next tool call.
Already delivered or queued messages are not recalled. Closing or archiving a coordinator does
not cancel its assigned tasks. Deleting a coordinator releases its assignments after the undo window; if the host cannot confirm that change, the coordinator remains available to retry. Disabling Labs hides entry points and grouping, but never widens
an existing coordinator's tool permissions.

## Tools and transcripts

Reuse list_tasks, get_task and send_message. For a coordinator, the host returns only explicitly
assigned tasks, including their current status. get_task returns a bounded local excerpt of recent
visible messages, without reasoning or raw tool output. start_task and cancel_task are rejected
for coordinators. Ordinary delegation retains its existing parent/child/sibling scope.

The host checks assignments again immediately before message delivery. Every delivered message
is written to both transcripts using the existing task message events, visibly identifying the
coordinator. The recipient receives a framed prompt that survives transcript replay. Running
tasks use the existing steering or queue behavior; idle tasks start a turn. A failed delivery is
reported by the tool. The coordinator reads replies with get_task; assigned tasks do not gain
access to one another or to the coordinator's other work.

## Presentation and recovery

Assigned tasks appear indented immediately below their coordinator, using the existing task row
and status language. Filtering, pinned tasks and archived coordinators must not hide an assigned
task. The picker keeps selected assignments and explains unavailable choices, empty projects and
save failures. Cancel leaves assignments unchanged; saving an empty selection releases all tasks. Editing assignments offers Undo, with a visible error if another coordinator has since claimed one.
No automatic prompt is sent when a coordinator is created: the user writes its objective. New-task autonomy defaults and mode hooks are skipped so they cannot override read-only creation. Clear Conversation and Change Agent are unavailable on coordinators in this slice; create a new coordinator and reassign tasks instead.

Membership survives app and host restarts. Native's usual host transcript and prompt persistence
carry message delivery. The scope remains in force even if the feature switch is later disabled.

## Verification

Baseline: the existing New Task path prepares the configured workspace; existing orchestration
only reaches delegated tasks and their family. No assignment or coordinator entry point exists.
On elara, GUI automation and before/after light/dark screenshots are unavailable. Visual checks
on the main Mac remain pending, with previews for the new picker and sidebar grouping.

Exercise scoped listing, summary bounds, unassigned reads/messages, revocation, self-assignment,
exclusive ownership, persistence, unsupported read-only settings and ordinary delegation in package
and real host tests. Build Debug, check iPad compilation, lint changed Swift files, and compile
Release and Nightly for preview guards. Keep the switch off by default throughout this slice.
