# One task history

A task keeps one durable, provider-neutral history on its host, whatever agents take part in it. The
history records what was said and done (the user's messages, agents' replies, tool calls, handoffs),
which agent session produced each item, and what each agent session has already seen. Switching back
to an agent the task already used reopens that agent's own conversation and sends it only what
happened while it was away. The transcript of a mixed-agent task is read from this history. It is the
foundation for forks, side chats and merge-back, which are designed here and built later.

This qualifies the 2026-10-17 "Durable by default" decision: conversations still live in each agent's
own store and still come back with `session/load`, but the host now also keeps its own bounded,
provider-neutral record of them. Agents remain the source of truth for their own replay; the history
is the source of truth for the task.

## What exists today

| Piece | Where | What it knows |
| --- | --- | --- |
| Host session | `sessions` table, `HostSession` | One open agent session: host id, agent, ACP session id, settings. Deleted when the session closes. |
| Session event log | `HostSession.log`, folded into `SessionMirror` | Everything the agent streamed since the last load. In memory only; a load starts it over. |
| Unfinished turn, queue, request ids | `turns`, `queue`, `requests` | The prompt in flight and its delivery, for recovery. Gone once the turn ends. |
| Earlier-conversation chain | `EarlierConversations` (app `UserDefaults`) | `later -> earlier` links for `/clear` and agent changes. App only: a paired iPad doesn't see it. |
| Change-agent context | `AgentModelContinuations` (app `UserDefaults`), `TaskHandoff` | A bounded excerpt of the source transcript, prepended to the next prompt once. |
| Orchestration tasks | `tasks` table, `HostTaskIdentity` | Parent and child tasks by agent session, remapped when an unsaved session is replaced. |

So no layer knows a task across agents. Every change of agent prepares a new agent session, even
when the task used that agent before (`ComposerAgentChange.continueWithSource`), and the context it
carries is cut from whatever the source session happens to show. The chain lives in one client.

## Model

Four records, all in the host's `host.sqlite` (schema version 14), with public types in ACP
(`Packages/ACP/Sources/ACP/TaskHistory/`) so the host, every client and other features share them.

```
task history (TaskHistoryID)          one per task
  participants                        agent sessions that took part, in join order
    ordinal, agent id, ACP session id, model, joined at, seen (watermark)
  items                               what happened, in order
    seq, source participant, turn (prompt request id), at, body
  transfers                           context delivered to a participant
    id, source history, target participant, range considered (from, through],
    items covered, strategy, state, request id, receipt
```

- **History.** `TaskHistoryID` is a host-allocated UUID. It records the folder and, for later
  forks and side chats, an optional lineage (`parent`, `kind`, `source seq`). Nothing reads lineage
  yet; the column exists so a fork never needs a migration.
- **Participant.** An agent session that took part, numbered from 1 in join order. Its key outside
  the history is `(agent id, ACP session id)`, unique across the store, which is how a session the
  host reopens finds its history again after the host session record was closed and deleted.
- **Item.** `seq` counts from 1 per history without gaps, assigned by the host inside the transaction
  that writes the item. Bodies are typed (`TaskHistoryItem.Body`): `user` (text, attachment names,
  origin, steered), `agent` (text), `thought` (text), `tool` (id, title, kind, status, paths, an input
  summary, an output excerpt), `plan` (entries), `turnEnded` (stop reason), `transfer` (a reference to
  context delivered), and `unknown` for bodies a newer host wrote. Each body is capped (16 KB; tool
  output excerpts at 2 KB) so the store grows with the conversation, not with tool output.
- **Transfer.** Context Native gave a participant about items it had not seen: `full` (a new agent
  session's first message), `delta` (switching back), or `client` (a handoff a client assembled, as
  the change-agent flow does today). It names the history its items come from (this one, or a fork
  for merge-back), the range it considered, and the items it actually conveyed, which a budget or
  an excerpt can make fewer than the range. Its receipt (what was selected and left out, and the
  text) is kept, so every handoff can be audited.

## Ids and correlation

Native ids are identity; agent ids are evidence. A participant is found by `(agent id, ACP session
id)` and never by an agent id alone. A turn is the `PromptParams.requestID` that started it, which
already deduplicates delivery (`requests`), so recording a turn twice (a retry, a recovery) replaces
its items instead of appending them again. A replay carries no request ids, so imported history gets
no turn ids and is matched to nothing. When an unsaved session is replaced under the same host id
(`replaceUnsaved`), the participant's ACP session id is updated in the same place the orchestration
tasks are remapped.

## Recording

The host records at the boundaries it already writes at, never per streamed token:

- **Turn start** (`startTurn`, inside the transaction that commits the turn): the user item.
- **Turn end** (`finish`, `fail`, a confirmed stop): the turn's items from the session mirror after
  the prompt (`turnItemsStart`), whole and capped, then `turnEnded`. Steered messages appear here as
  user items with `steered` set.
- **Recovery**: the recovered turn records from its original prompt's position in the replay, so the
  part the crash cut off is kept.
- **Import**: a session adopted from the agent's list whose participant has no items imports its
  replay once, with no times, so tasks that predate the history are complete.

Only user and orchestration sessions record; announced subagents are covered by their parent's
items. Hidden commands (`/context`) don't record. A recording failure is logged and never fails a
turn.

## Watermarks and coverage

A participant has seen an item if it produced it (including the prompts it received) or a delivered
transfer conveyed it. Considering an item is not conveying it: an item a transfer left out (for its
budget, or because an excerpt skipped it) stays missing and is offered again next time, newest
first, so a budget never silently marks anything seen. The one exception is what a delta never
replays by design (reasoning, tool state, turn endings): offering it again would never send it, so a
delivered delta covers it, or a single tool call would hold a watermark back for good. Its watermark `seen` is the highest seq below which it has seen everything,
advanced whenever an item is recorded or a transfer is delivered. Gaps are honest: an agent that kept
working while another agent's turns happened in between has its own later items but a watermark
stuck at the gap. What a participant is missing (`TaskHistoryCoverage.missing`) is every item above
its watermark that it neither produced nor received. That set is the delta.

A transfer is `prepared` when a switch commits, `sent` when the turn carrying it starts, `delivered`
when that turn ends with the agent's answer or is found in the agent's replay, and `superseded` when
the switch is undone. Watermarks only move on `delivered`.

## Switching back with a delta

Behind the Labs gate `task-history` (default off; off keeps today's behavior exactly).

1. Choosing an agent in the composer asks the host for the task's participants. If one ran on the
   chosen agent on this same host and the agent can load sessions, the change reuses it: the app
   reopens that conversation (as Undo already does), applies the chosen model and permissions to it
   through the existing `ComposerAgentChange` steps, and asks the host to prepare a `delta` transfer
   (`_native/history/join` again: a session already in the history is returning, so the host
   prepares a delta of what it missed instead of recording a client handoff, and the client sends
   none).
   Otherwise the change prepares a fresh session exactly as today, and the host records the client's
   handoff as a `client` transfer.
2. The delta is rendered lazily, when the next message starts its turn on the host, so it covers
   everything up to that moment. The host puts it ahead of the message as a framed preamble block
   (`<native_instructions id="task-history:<transfer id>" label="Earlier context">`), stored with the
   turn, so a retry or a recovery resends the same context and never renders a second one. The
   agent's replay reads the frame back as a quiet marker, as with modes today.
3. Selection and rendering are the budgeted handoff's (whole items, a budget, omissions, a typed
   receipt), not a second implementation: the history supplies the missing items, the handoff
   selects and renders them, and the history records the items its receipt says were conveyed.
   Reasoning and raw tool output stay out; context from another agent is framed as context, not
   instructions. This slice starts once that handoff work is on main.

A conversation is returned to only when it has taken a message, isn't waiting for a handoff of
its own, and is in the same task history as the current one on the same host. Otherwise (the agent
dropped it, can't load, policy forbids it, or it's from before the gate or set aside by `/clear`)
the change starts a new conversation with a handoff, as before. A reused session is never closed or
deleted by Cancel or Undo; Undo supersedes its prepared transfer (`_native/history/withdraw`) and
restores the source. A return's Undo lasts until the conversation starts a turn, from any client,
or the app quits: only the host knows whether it continued while Native was closed, so after a
relaunch it starts closed. The app's earlier-conversation chain stays one line: the returned
conversation moves to the front and the one that followed it takes its place.

## The transcript

Also behind `task-history`. A participant's own transcript stays what its agent replays and streams
(`SessionState`, unchanged). A conversation that a change of agent started shows, above the "Continued
with" divider at its top, the items its handoff transfer considered that other participants produced
(`_native/history/summary`, then `_native/history/read`), read-only, under the name of the agent that
produced them: the newest 40 messages and tool calls, saying when older ones are left out. Reasoning,
plans and turn endings stay out. Where a host transfer's `task-history:` marker appears later in a
transcript (a switch back, slice 4), it shows the items that transfer covered in place the same way.
So the user reads one conversation in order, whichever agent is current, and nothing is shown twice:
each item appears once, either in its own agent's replay or where the context it belongs to was
handed over.

The handoff's place is the top of the new conversation rather than its marker: the change-agent flow
sends its context as a content block, which the host doesn't echo as a marker until the agent replays
it, and a mode's instructions can take the message's one marker.

## Storage, migration and retention

- Schema version 14 adds `histories`, `history_participants`, `history_items` and
  `history_transfers`. An older host ignores tables it doesn't know, so downgrading is safe.
- Existing open host sessions get a history when they next start a turn or load. A change of agent
  joins the new conversation to the task's history when it prepares it, before its first message
  (the app's task-start hook calls `_native/history/join` with the earlier conversation's agent
  session), so the new conversation's items continue the task's numbering. `/clear` and other
  restarts of the same agent don't join: they leave the earlier context behind on purpose. Chains
  from before the gate was on keep a history per conversation and today's transcript: joining a
  conversation that already has items would renumber them, and items are never renumbered.
- Retention follows the task. Deleting a task deletes its participants (`deleteAgentSession`, and
  `_native/history/forget` from the app's expired deletion for agents that can't delete), and a
  history with no participants is deleted with its items and transfers. Archiving keeps it. The data
  lifecycle inventory lists the new tables.

## Failure and recovery

- **Host restart.** Items and transfers are committed with the turn they belong to, so a restart
  loses nothing a turn hadn't committed. A `sent` transfer whose turn recovery finds in the replay
  becomes `delivered`; one whose prompt never arrived is resent with that prompt.
- **An agent that can't load.** Reuse needs `session/load`; without it the change falls back to a
  fresh session with a full transfer. A reused session that fails to load during the change leaves
  the source selected with the reason, as any failed preparation does today.
- **Partial delivery.** A turn that fails before the agent answers keeps its transfer `sent`; the
  retry carries the same text. Native never claims delivery it can't see, and never renders a second
  transfer while one is `sent`.
- **Store errors.** Recording and reads are best effort for the conversation (a turn never fails
  because history couldn't be written), and strict for transfers: a delta that can't be committed
  holds the message first in the paused queue with the reason, since sending it without the context
  would mislead the agent.

## Multi-client and iPad

The history lives on the host, so every client of that host sees the same one: the Mac, an iPad, a
Mac paired to a Mac mini. Methods follow the session permissions clients already have; reading
history needs the same grant as attaching to the session. A change of agent stays on the task's
host, as today. Without a host (agents running in the app) there is no history and nothing changes.

## Forks, side chats and merge-back (later)

The model is built so these need no migration:

- A fork is a new history with lineage `{parent history, kind: fork, parent seq}`. Its own items
  number from 1 like any history's; the parent's items up to the parent seq are never copied but
  reach the fork's first participant as a `full` transfer whose source is the parent history, or a
  native fork where the agent negotiates one (never assumed).
- A side chat is a fork shown only inside its parent.
- Merge-back is a `delta` transfer whose source is the fork's history, covering the fork's own items
  after its last merge-back, into the parent's current participant: the same coverage and rendering
  as switching back. Because every transfer names its source history, a parent's seq 5 and a fork's
  seq 5 never mix.

## What other work can rely on

- `TaskHistoryID`, `TaskHistoryItem`, `TaskHistoryParticipant`, `TaskHistoryTransfer` (ACP): stable,
  `Codable`, with unknown cases for newer values.
- `TaskHistoryCoverage.missing(for:)` and the watermark: what a participant hasn't seen.
- On the host: `_native/history/summary` (participants, watermarks, transfers), `_native/history/read`
  (items), `_native/history/missing` (what a session hasn't seen) and `_native/history/join` (a change
  of agent joins the task, with what its handoff conveyed).
- Switching back uses the budgeted handoff's selection and receipt; the history only says what is
  missing and records what the receipt conveyed.
- Capability work can take "same session" evidence from the participant list rather than agent names.

## Slices

Each is one pull request, small enough to review in one sitting.

1. **Store and migration.** Schema 14, `HostStore+History`, ACP types, a history per new or adopted
   host session, participants found by agent session, `summary`/`read`, retention, the data
   inventory. No behavior change.
2. **Recording.** User items at turn start, the turn's items at its end, recovery, import of earlier
   history. Tests on captured Claude Code and Codex traffic. No behavior change.
3. **Watermarks.** Coverage, `seen`, transfers and their states, `_native/history/join` for a
   committed change of agent with its handoff's conveyed items, `_native/history/missing`. No
   behavior change until the change-agent flow calls `join`.
4. **Switch back with a delta.** After the budgeted handoff work is on main, building on its
   selection and receipt: the `task-history` gate, reuse of the earlier session in the change flow,
   the host's lazy delta in the turn, Undo, fallback, a linear chain.
5. **Transcript from the history.** A change of agent joins the task's history as it prepares the new
   conversation, and the new conversation's transcript shows the agents before it, above the divider.
   Host transfers' markers expand in place once slice 4 renders them.

## Not doing

A second orchestration architecture, hosted relays, other apps' secrets, assuming every agent can fork,
resume or roll back, or anyone else's tool catalog and prompts. Native stays ACP, the host and
plugins.
