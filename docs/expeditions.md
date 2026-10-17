# Expeditions

An expedition is a large objective that a crew of agents carries out over hours, from a route the
user approved: a lead plans it, builders do the work in a workspace of its own, a reviewer checks
each leg, and the user is asked only when it matters. It ends with a debrief and a pull request.

It's Native's take on the idea behind the reference app's Missions (`research/factory-missions.md`): learned
from, not copied. No code, prompts, text, assets or vocabulary of the reference app's appear in Native.

## The name

| Name | Why it fits |
| --- | --- |
| **Expeditions** (chosen) | A crew sets out on a long objective with a route and provisions, checks in at camps and comes back with a report. Reads clearly in a menu ("New Expedition…") and gives a coherent vocabulary: route, legs, crew, logbook, debrief. |
| Constellations | Agents as stars joined into one figure: the strongest tie to Native's interlocking mark and Nightly's night sky, and the team view can literally draw one. Weaker as a verb and long in a sidebar. |
| Voyages | The same journey idea in a shorter word, with a nod to navigating by the stars. Slightly whimsical for work that runs for hours. |
| Ensembles | Many voices performing one piece: puts the cross-provider crew first. Says less about planning, progress and arriving. |

The sub-terms below follow the recommended name. With Constellations or Ensembles they'd change
(the route becomes a chart or a score), but the concepts don't.

## What we took, and what we didn't

From the research (`research/factory-missions.md`):

- **Taken:** an engine that isn't an LLM runs the queue while an agent plans; structured handoffs
  (a builder's report says what changed, how it was verified, and what it left undone); review by a
  different provider than the builder by default; bounded attempts before the user is asked; a
  guard on scope growth (a lead revision that more than doubles the route needs approval); agent
  state shown as waiting on you, working, idle; a readiness check before anything starts.
- **Done differently:** a budget per expedition (the reference app has none); worktree isolation by default;
  the crew picked by the user across providers; protection that doesn't depend on which tool an
  agent writes with (Native is the only writer and checks the files); steering a running member
  without pausing the whole run; a pull request that's part of the finish, not whatever an agent
  happened to open.
- **Left out:** organization billing and "teams" as attribution; hidden cloud machines; free-text
  dependencies.

## Vocabulary

| Term | Means |
| --- | --- |
| Objective | What the user wants done, in their words. |
| Route | The plan: legs in order, each made of assignments. The lead proposes it; the user approves it. |
| Leg | A stretch of the route that ends at a checkpoint: "what's true when this leg is done". |
| Assignment | One piece of work for one crew member: a brief, "done when" criteria, what it comes after. |
| Checkpoint | The reviewer's check of a finished leg against its criteria: pass, or changes with findings. |
| Crew | The agents on the expedition: a lead, one or more builders, a reviewer. Any provider in any role. |
| Report | What a builder hands back when an assignment is done (its final reply). |
| Logbook | The expedition's timeline: what happened, when, and who did it. |
| Base | The expedition's workspace: a worktree on its own branch, so the user's checkout is untouched. |
| Debrief | The lead's summary at the end, which becomes the pull request's description. |

"Task" stays what it is everywhere else in Native (a session), which is why plan items are
assignments.

## What's new, and what's composed

Most of an expedition is pieces Native already has. Only the parts in bold are new.

| Need | Built from |
| --- | --- |
| Keep a builder going until its assignment is done, within budget | `GoalLoop`, `GoalBudget`, `GoalMarker`, `TurnOutcome` (`NativeAutomation`) |
| Events in, effects out; persistence; interrupted-on-relaunch; gates | The workflow engine's shape (`WorkflowRun`, `WorkflowRunner`, `WorkflowRunStore`), reused as a pattern |
| Crew members as sessions on any agent, reopened after a restart | `AppModel.startTaskSession` / `reopenTaskSession`, like workflow steps |
| Isolation | A task worktree from the Git feature (`GitStore.createTaskWorktree`) |
| Pull request at the end | The GitHub feature's hook, exactly as workflows' pull request step uses it |
| Provider limits and their reset times | The Usage feature's `UsageLimits` (`limitStatus(for:)`, its wording) |
| Running while the app is closed | The durable host, once engines move into it (Phase 3 of `docs/durability.md`) |
| **Proposal and approval** | A route protocol the lead answers in, a review screen, approval as a one-way door |
| **Roles** | Lead, builder, reviewer: prompts and scheduling per role |
| **Checkpoints** | A verdict protocol, fix rounds, escalation |
| **Shared artifacts and progress** | Route, reports, verdicts, logbook, debrief; rendered to protected files |
| **The crew view** | The overview, per-member views, attention cards |
| **Expedition budget** | Cost and time across the whole crew, on top of each assignment's goal budget |

Where it lives:

- `Packages/Expeditions` (module `NativeExpeditions`): the engine. UI-free, Swift Testing tests,
  macOS and iOS, depends only on `NativeAutomation`. The state machine (`Expedition`), its events
  and effects, the route and its parser, the verdict marker, prompts, budget, attention items,
  readiness checks, the document renderer, the store and the observable runner with its
  `ExpeditionHost` protocol.
- `native/Expeditions/`: the built-in plugin, the app's host adapter (sessions, worktree, pull
  request, limits, notifications) and every view.

### Why Native's engine schedules, not the lead

The lead is an agent that plans, answers and summarizes. It doesn't start builders itself through
`start_task`; Native's engine does, from the approved route. That gives:

- **One source of truth.** The route, every assignment's state and every cost live in the engine,
  so the overview, recovery and budgets never depend on an agent remembering to call a tool.
- **Durability.** A pure state machine survives a crash and moves into the host unchanged.
- **Cross-provider by design.** The user picks the crew; any agent can lead, build or review,
  and the lead never needs Native's MCP tools (which some agents won't call reliably).
- **Budgets that hold.** Native decides whether the next turn goes out, between turns, as goals do.

Agents still talk to each other through Native: a builder's report reaches the reviewer, findings
reach a builder, and the lead revises the route at leg boundaries. Orchestration's tools stay
available to every session for ad hoc delegation inside an assignment.

## Lifecycle

```
 planning ──route──▶ reviewing ──approve──▶ underway ──all legs pass──▶ debriefing ──▶ complete
    ▲                   │                     │  ▲
    └──ask for changes──┘                     │  └── resume ── paused / needs you / limited
                        └──discard──▶ stopped ◀── stop
```

| Phase | Means | Task status (sidebar, cards) |
| --- | --- | --- |
| `planning` | The lead is reading the project and drafting the route (or revising it). | working |
| `reviewing` | A route waits for the user. | needs plan response |
| `underway` | Assignments and checkpoints are running. | working |
| `paused` | The user paused: turns in flight finish, nothing new goes out. | paused |
| `needsYou` | Something waits on the user: a question, a failed checkpoint, a budget, a route change. | needs input |
| `limited` | A provider limit stopped the crew; work resumes at the reset. | limited |
| `debriefing` | Every leg passed; the lead commits leftovers and writes the debrief; the PR opens. | working |
| `complete` | Done: debrief written, pull request opened if asked for. | done |
| `stopped` | The user stopped it, or discarded the route. Sessions and the worktree stay. | cancelled |

Phases are computed from facts (as `WorkflowRun.phase` is), never stored, so they can't disagree
with the assignments they summarize.

## Proposing and approving

**New Expedition** (⌥⌘E, or the Expeditions page) asks for:

- the **objective**, in the user's words;
- the **project**, and the **base**: a new worktree on `<prefix>/expedition-<slug>` (default) or the
  current checkout;
- the **crew**: a lead, builders (one or more agents) and a reviewer, each from the ready agents.
  Defaults: the last-used agent leads, every ready agent builds, and the reviewer is a different
  provider than the builders when there is one ("built by Codex, checked by Claude Code");
- the **budget**: total cost and active time, both optional, and whether to open a pull request.

**Readiness** is checked before anything starts, inline in the sheet, as warnings with a fix
rather than errors, except the one hard stop (no ready agent):

| Check | Says |
| --- | --- |
| A crew agent isn't installed or signed in | which agent, and its install or sign-in step |
| The project isn't a git repository | a worktree needs git; offer to run in the current folder instead |
| Uncommitted changes in the project | they won't be in the new worktree; commit or stash first, or run in place |
| Reviewer is the same provider as every builder | a different one catches more |
| No budget | the expedition stops only at the per-assignment iteration ceiling |
| Pull request asked for but `gh` isn't signed in | `gh auth login`, or turn the PR off |

**Planning.** Native makes the base, starts the lead there and sends the planning prompt: the
objective, the crew (agent ids and names, so the lead can match work to strengths), the budget, and
the route protocol. The lead explores without changing files and ends its reply with one `<route>`
block of JSON:

```json
{
  "summary": "How the work will be approached, in a few sentences.",
  "legs": [
    {
      "title": "Export pipeline",
      "outcome": "CSV export works from the command line, with tests.",
      "assignments": [
        {
          "id": "csv-writer",
          "title": "Add the CSV writer",
          "brief": "What to do, where, and anything to watch out for.",
          "doneWhen": ["Writes RFC 4180 CSV", "Unit tests cover quoting"],
          "assignee": "codex",
          "after": []
        }
      ]
    }
  ],
  "questions": ["Should empty cells be quoted?"],
  "assumptions": ["UTF-8 output only"]
}
```

Native parses it forgivingly (fences, prose around it, missing optional fields) and strictly where
it matters (unique ids, `after` naming earlier assignments, no cycles, assignees in the crew). A
route that doesn't parse goes back to the lead with the exact problem, twice at most; then the user
sees the lead's reply and can ask again or stop.

**Review.** The route opens as a document, not a form: the summary; the lead's questions, each with
an answer field (answers travel with every assignment's brief); assumptions; then the legs, each
assignment showing its assignee, brief, "done when" list and what it comes after. Everything is
editable in place: titles, briefs and criteria, the assignee (any crew agent), and removing an
assignment. Three ways out:

- **Approve and Set Out** (⌘Y, or ⌘Return on the page). Approval is the one-way door: the route
  becomes the contract, and the sheet says so.
- **Ask for Changes**: a note to the lead, which revises the route (back to `planning`). The revised
  route shows what changed since the last one.
- **Discard** (⌘⇧⌫): stops the expedition. The worktree stays until the expedition is removed.

## Running

The engine schedules from the route:

- Legs run in order. Within a leg, an assignment starts once everything in its `after` is done, up
  to the expedition's parallel limit. The limit is 1 by default, because the crew shares the base;
  raising it is a setting with a warning, until per-assignment worktrees with merge-back exist.
- Each assignment gets a fresh session on its assignee in the base, driven by a `GoalLoop` whose
  objective is the brief plus "done when", with the route summary, the user's answers and the
  reports it comes after inlined. Builders commit their work when an assignment is done, so the
  branch tells the story.
- When a leg's assignments are done, its **checkpoint** runs: a fresh reviewer session gets the
  leg's outcome, every assignment's criteria and report, and is asked to inspect the changes and run
  the tests. It ends with `VERDICT: pass - <note>` or `VERDICT: changes - <summary>`, findings above.
- **Changes** start a fix round: the findings go to the session of the leg's last builder, as a
  goal. Then the reviewer checks again in its own session. After two rounds (a setting), the
  checkpoint waits on the user: accept anyway, another round, or stop.
- At a **leg boundary** with legs still ahead, the lead gets the leg's reports and verdict and may
  answer with a revised `<route>` for the legs ahead. Changes that only touch assignments that
  haven't started apply on their own and are logged with what changed; anything that removes or
  rewrites approved work waits for the user as a route change card.
- When every leg has passed, the lead is asked to commit anything left and write the **debrief**:
  what was done per leg, what the checkpoints verified, follow-ups and risks. Then the pull request
  opens, if asked for.

## Shared artifacts, and why they're protected

The expedition's artifacts are the objective, the approved route and its revisions, the user's
answers, every report, every verdict with its findings, the logbook and the debrief. The engine's
state is the record. Native renders it to Markdown in `~/.native/expeditions/<id>/` (`route.md`,
`reports/<assignment>.md`, `checkpoints/<leg>.md`, `logbook.md`, `debrief.md`): outside the repo,
like worktrees, so they never end up in a commit or a file watcher, and the user can open them in
any editor.

Agents never need to write those files: everything an agent needs is in its prompt, and everything
it hands back travels in its reply, through a protocol Native parses and validates (the route
block, the goal status line, the verdict). Native is the only writer, because:

- the route is the contract the user approved; a builder that could edit it could loosen its own
  "done when" or mark itself finished;
- reports and verdicts are the record a reviewer and the user rely on; they must say what the
  agent said when it said it;
- only the right role changes the right thing: a route block counts only from the lead, a verdict
  only from the reviewer, a status line only for the assignment its session is on.

The files are written read-only, and Native remembers what it wrote. If one changes anyway (any
agent can `chmod`), Native puts its own copy back and logs which file and when.

## The overview

The Expeditions page lists expeditions, newest first, with phase, progress and cost, and starts new
ones. An expedition opens on its own page:

```
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │ ◇ Add CSV export to reports                         [Pause] [Stop]           │
 │   app · expedition-csv-export · started 42m ago · $3.12 of $10 · 31m active   │
 │   UNDERWAY ▮▮▮▮▮▮▯▯▯▯  4 of 7 assignments · leg 2 of 3                         │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ NEEDS YOU                                                                    │
 │ ┌ Codex is blocked on "Wire the export button" ─────────────────────────────┐ │
 │ │ "Should the button live in the toolbar or the File menu?"   [Reply…]      │ │
 │ └───────────────────────────────────────────────────────────────────────────┘ │
 ├──────────────────────────────────────────┬───────────────────────────────────┤
 │ ROUTE                                    │ CREW                              │
 │ ● Leg 1 · Export pipeline        passed  │ ✳ Claude Code  lead     idle      │
 │   ✓ Add the CSV writer   Codex   12m $.8 │ ⌘ Codex        builder  working   │
 │   ✓ Stream large reports Codex    9m $.6 │   "Running swift test…"           │
 │   ✓ Checkpoint  Claude Code  pass        │ ✳ Claude Code  reviewer idle      │
 │ ◐ Leg 2 · UI                             │                                   │
 │   ◐ Wire the export button  Codex  ⚠     │ LOGBOOK                           │
 │   ○ Progress indicator      Codex        │ 3:02 Checkpoint 1 passed          │
 │ ○ Leg 3 · Docs                           │ 2:51 Codex finished "Stream…"     │
 └──────────────────────────────────────────┴───────────────────────────────────┘
```

- **Header**: the objective's first line; project, branch, age, cost against budget, active time;
  the phase badge; a segmented bar with one segment per assignment, colored by status; Pause or
  Resume, and Stop.
- **Needs you**: one card per item, oldest first, each with its single primary action and the
  context to decide. Kinds: route to review, route change, blocked assignment (reply), failed
  checkpoint after its rounds, budget reached, provider limit (with the Usage feature's exact reset
  wording and Resume at Reset), assignment failed to start or crashed twice, Native quit mid-run.
  ⌘Y and ⌘⇧⌫ answer the oldest approval (route, route change), like every other approval card.
- **Route**: legs and their assignments as a timeline, each with status glyph, assignee, elapsed
  time and cost, and the checkpoint row with its verdict and rounds. Selecting one opens its
  session beside the page.
- **Crew**: each member with its agent, role, what it's doing right now (the session's activity
  line, never just "Working…"), and its cost. Selecting one opens its current session.
- **Logbook**: the latest entries; the whole thing opens as a list.
- **Artifacts**: reports and verdicts open from their rows; "Show Files" reveals the folder (Mac).

Narrow widths stack the crew and logbook under the route. Every hover affordance has a visible or
context-menu equivalent.

**Per-member view.** The inspector shows the selected assignment's or member's session transcript
(the same transcript view the rest of Native uses), its status and reason, and a message field.

## Steering and intervening

| The user wants to | They |
| --- | --- |
| Tell a builder something mid-assignment | write in its message field: steered into the running turn where the agent supports it, queued otherwise, and the field says which |
| Answer a blocked builder | reply on its card or in its field; the goal picks back up |
| Talk to the lead | the lead's field (⌘L focuses it on the expedition page); answers that change the route come back as a route change |
| Hold everything | Pause: running turns finish, nothing new goes out; Resume picks up where it was |
| Stop one assignment's turn | Stop on its row |
| Redo, skip or accept an assignment | Retry (fresh session), Skip (later work goes on without it), Accept (its latest reply becomes the report) |
| Change the crew | reassign a stopped or waiting assignment to another agent; add or remove a builder; swap the reviewer for checkpoints ahead. Pending work of a removed builder moves to the remaining ones |
| Stop the expedition | Stop: every turn is cancelled; sessions, reports and the worktree stay |

Every action is a model method (`ExpeditionRunner.send(_:to:)`), so the iPad and future clients
drive the same ones.

## Budgets and limits

- **Expedition budget**: total cost (summed across members' sessions, where agents report cost)
  and active time. Checked between turns, never mid-turn (a half-finished edit is worse than a late
  stop). When it's reached, nothing new goes out and a card offers **Add the same again**, **Wrap Up**
  (skip what's left and go straight to the debrief) or **Stop**.
- **Per assignment**: a goal budget (iterations, default 15) so no builder loops; per checkpoint, a
  number of fix rounds (default 2).
- **Provider limits**: an assignment stopped by a limit is `limited`. The card uses the Usage
  feature's wording ("Codex · 5-hour limit reached · resets 3:05 PM, in 42 min"), and Resume at
  Reset is on by default for expeditions: the engine resumes the assignment when Usage's reset time
  arrives. Other providers' members keep working meanwhile.

## The finish

The debrief is a card at the top of a complete expedition: the lead's summary, the legs with their
verdicts, cost and time, and the pull request. The PR is opened through the GitHub feature's hook
(push the branch if needed, then `gh pr create`), titled from the objective, with the debrief as its
body, as a draft when the user chose that. If it fails (not on a branch, push rejected, `gh` signed
out) the card says why and offers the fix and Retry; the debrief is still there to copy.

## Recovery

- **Today** the engine runs in the app, like workflows: state is saved after every event
  (`expeditions.json` in Application Support, plus session records for reopening). On relaunch,
  assignments that were working become interrupted, and the expedition shows "Native quit while 2
  crew members were working" with Resume, which reopens their sessions and tells each agent its turn
  was cut off.
- **An agent crashes mid-assignment**: the turn fails, and the engine resumes it once on its own
  with the interrupted prompt (unattended runs shouldn't stall on one crash); a second failure waits
  on the user. Workflows never retry on their own; expeditions run for hours unattended, which is
  why they get exactly one.
- **With the durable host** (Phase 3), the runner moves into the host unchanged, its state into the
  host store (`expeditions` table), and the host's `RecoveryPlanner` resumes interrupted turns
  itself: the app quitting doesn't stop the crew at all.

## Notifications

When Native is in the background: a route is ready to review, the expedition needs you (with the
card's text), a provider limit stopped it (with the reset time), and it's complete (with the PR).
Assignments finishing don't notify; the logbook has them. Expedition sessions are task sessions, so
the Notifications plugin should skip their turn ends (a one-line change for its owner).

## Keyboard

Proposed rows for `docs/keyboard.md` (checked against every row there and the standard menus):

| Keys | Action | Menu |
| --- | --- | --- |
| ⌥⌘E | New expedition | File |
| ⌘⇧X | Expeditions | Go |
| ⌘Y / ⌘⇧⌫ | Approve / discard the route waiting for review, or a route change (the existing approval keys) | |
| ⌘Return | Approve the route, on the review page | |
| ⌘L | Focus the lead's message field, on an expedition's page (the existing focus-composer key) | Session |

Pause, Resume and Stop Expedition are menu commands without keys (Session menu).

## iPad

The engine is a package that builds for iOS, and the views use no AppKit ("Show Files" is the one
Mac-only action, behind the platform adapter, absent on iPad). On iPad an expedition runs on a host
and the iPad mirrors it: the host protocol gains `_native/expeditions/list`, `…/subscribe` (state
snapshots after each event) and `…/send {id, event}`. Events in and state out is already the
runner's whole API, so the mirror is thin.

## Minimal by default

Expeditions is a built-in plugin, off by default. Until it's on, or an expedition exists, there's
no sidebar item. File ▸ New Expedition… is always there; the first time, it explains what an
expedition is and turns the plugin on. Settings ▸ Extensions turns it off again.

## Settings

Per expedition, in the New Expedition sheet: crew, base, budget, pull request. App-wide (Settings ▸
Extensions ▸ Expeditions): default reviewer rule (different provider when possible), fix rounds per
checkpoint (2), iterations per assignment (15), parallel assignments (1), Resume at Reset (on).
