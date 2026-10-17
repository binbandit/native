# Factory Missions: how they work

Research notes for designing Native's own long-horizon multi-agent feature. Source is the read-only
rebuild at `~/developer/reverse/factory/factory-clone`. Path shorthands:

- `cli/` = `apps/cli/src/` (the `droid` CLI and agent runtime, which the desktop app also drives)
- `fe/` = `packages/frontend/src/` (desktop and web UI)
- `sdk/` = `packages/droid-sdk-core/src/protocol/` (wire types and enums)
- `common/` = `packages/common/src/`, `utils/` = `packages/utils/src/`, `rt/` = `packages/runtime/`

**Two generations coexist.** Most machinery belongs to **Missions 1.0** (internally "mission
decomposition"): an orchestrator plus a deterministic runner that feeds one worker at a time from a
feature queue, with auto-injected validators. **Missions 2.0** (flag `MissionsV2`, tag `mission-v2`)
is a thinner, message-based design: an orchestrator spawns long-lived agents on local or cloud
machines and talks to them by message. Users pick a version in settings
(`fe/settings/missions/MissionVersionSelector.tsx`); `/missions` lists both. "v1" and "v2" below
mean these two.

`fe/app/MissionControlOverlay.tsx` is unrelated to missions: it detects macOS Mission Control (the OS
window overview, via a JXA poll of Dock windows in `apps/desktop/src/main/windows/missionControl.ts`)
and overlays the session title. Missions' Mission Control lives in `fe/missions/` and
`cli/components/mission-control/`.

---

## 1. What a mission is

A mission is a long-running, multi-session project ("hours or days" per onboarding copy) that an
orchestrator plans with the user, gets approved as a written proposal, and executes by delegating to
other agent sessions, with progress persisted outside any one conversation so it survives pauses,
crashes, and restarts. In v1 the plan is materialized as files (feature queue, validation contract,
worker skills, environment manifest) and a non-LLM runner drives execution. In v2 the plan lives in
the orchestrator's context plus a shared document space, and execution is a team of persistent agents
reporting back by message.

- **vs a single session:** a mission has a dedicated orchestrator (session type upgraded to
  `orchestrator`, `DroidInteractionMode.Mission`) that is told every turn not to write code itself
  (a system reminder in `cli/core/AgentLoop.ts`, not a tool restriction).
- **vs a subagent (Task tool):** subagents run inside the parent's turn and return a value. Mission
  workers are independent top-level sessions spawned through the daemon (tags `exec`,
  `mission-worker`), with their own transcripts, resumable after a pause, handing off through a
  structured tool. Orchestrators and validators still use Task subagents for research and reviews.
- **vs spec mode:** `DroidInteractionMode.Spec` is a read-only planning pass ending in
  `ExitSpecMode`, after which the same session implements. The mission proposal reuses the spec
  review UI (`fe/missions/MissionSpecReviewPanel.tsx`, `SpecReviewKind.Mission`, downloads as
  `mission-proposal.md`), but approval creates a mission directory and starts delegated execution.

---

## 2. Lifecycle (v1)

`MissionState` in `sdk/droid/enums.ts`, persisted in `state.json`:

| State | Meaning | Written by |
| --- | --- | --- |
| `planning` | Planning with the user; no run yet | `MissionFileService.ensurePlanningState` on the first user turn of an orchestrator session (`cli/core/AgentLoop.ts`) |
| `awaiting_input` | Idle, waiting on the user | Interrupt during planning, or `withMissionAwaitingUserInput` while an orchestrator turn blocks on AskUser or a permission (`cli/services/mission/missionRunnerOperations.ts`) |
| `initializing` | Documented as "authoring artifacts after acceptance" | Only written if `StartMissionRun` finds no state file. Acceptance actually leaves `planning` until the run starts, so this looks vestigial (ambiguous) |
| `running` | Runner spawns and monitors workers; orchestrator chat disabled | `StartMissionRun` executor |
| `paused` | Resumable stop | User pause, abort of the blocking tool call, CLI exit, or auto-pause |
| `orchestrator_turn` | A worker returned control or failed; orchestrator acts next | `EndFeatureRun` and the runner |
| `completed` | All features completed or cancelled. Terminal | Runner when the queue drains, or `completeMissionAtOrchestratorTurnEnd` |

There is no failed or cancelled mission state. Failure is a pause with a structured
`MissionPauseReason`: `unrecoverable_usage_402`, `feature_retry_limit_exceeded`,
`scope_growth_limit_exceeded` (absent = user or runner pause). Features, not missions, can be
`cancelled`. A mission is abandoned by exiting it (`handleExitMission` in `cli/app.tsx`: pause, then
downgrade the session to a normal one).

Flow:

1. **Entry.** `/missions` -> "Begin new mission", Mission mode in the desktop composer, or
   `droid exec --mission`. Access check, readiness gate, onboarding (sections 7, 15), then
   `enterMissionMode()` (`cli/services/mission/enterMissionMode.ts`) upgrades the session.
2. **Planning.** Built-in skills `mission-planning` and `define-mission-skills`
   (`cli/skills/builtin/builtinSkillDefinitions.ts`): interview, research via subagents, verify
   dependencies and the validation toolchain, get explicit sign-off on infrastructure, testing, and
   milestones.
3. **Proposal.** `ProposeMission` requires confirmation: proceed, proceed with a comment (returned as
   `llmGuidance`), or reject with a reason. A "Manually edit mission" string and `isEdited` field
   exist, but `MissionProposalAction` is only `approve | approve-with-comment | reject` (likely dead).
   Accepting creates the mission dir, `working_directory.txt`, `mission.md`, a frozen model snapshot,
   and logs `mission_accepted`. Headless exec auto-approves.
4. **Artifacts.** A system reminder lists the files to author; the orchestrator writes them.
5. **Run.** `StartMissionRun` validates preconditions, sets `running`, logs `mission_run_started`, and
   blocks while `MissionRunner` loops. It returns on a handoff needing attention, a pause, or
   completion, with handoff summaries.
6. **Orchestrator turn.** Triage handoffs, edit `features.json` or dismiss items, call
   `StartMissionRun` again, until `completed`.

Every transition is also appended to `progress_log.jsonl` (`ProgressLogEntryType`):
`mission_accepted`, `mission_paused` (+`pauseReason`), `mission_resumed`, `mission_run_started`,
`worker_started` (+model, +`substitutedFromModelId`), `worker_selected_feature`, `worker_completed`
(+handoff), `worker_failed` (+`failureReason`), `worker_paused`, `handoff_items_dismissed`,
`milestone_validation_triggered`. Active time is summed from run-start or resume to pause intervals
in this log (`utils/mission/missionElapsedTime.ts`).

**v2 has no mission state machine.** Sessions are just idle, pending, or running
(`DroidExecutionStatus`) with an optional attention (`permission` or `ask-user`). I found no
mission-level paused or completed state.

---

## 3. Agent roles

`DecompSessionType` (`sdk/droid/enums.ts`) has two values:

- **`orchestrator`**: user-facing; plans, writes mission artifacts, triages handoffs. Adds
  `ProposeMission`, `StartMissionRun`, `DismissHandoffItems` (`ORCHESTRATOR_TOOL_IDS`,
  `cli/agent/tools.ts`).
- **`worker`**: one feature per session. Gets `EndFeatureRun`; loses orchestrator tools, AskUser,
  ProposeWorkstream, settings staging, and TodoWrite (`WORKER_FORBIDDEN_TOOL_IDS`,
  `isUnattendedSession` in `cli/utils/toolAvailability.ts`).

**Validators are workers** whose feature `skillName` is `scrutiny-validator` or
`user-testing-validator` (`VALIDATION_SKILL_NAMES`). The UI labels them "Validator #n" and the rest
"Worker #n". Other worker types are mission-authored skills (say `backend-worker`), each a
`skills/<type>/SKILL.md` in the mission dir.

**Models.** Three slots, each model plus reasoning effort: orchestrator, worker, validation worker
(`MissionModelSettingsSchema` in `sdk/settings/schema.ts`). Constants in `utils/llm/constants.ts`
show the intent: feature workers on a Claude Opus model, validators and orchestrator on a GPT model,
orchestrator at high reasoning, so implementers and validators run on different vendors. If the
user's model is on `MISSION_ORCHESTRATOR_RECOMMENDED_MODELS` it is kept (effort raised to at least
high), else the configured orchestrator model is swapped in. With nothing stored, the settings
service falls back to the general default model, so which default wins is ambiguous. Each spawn
re-checks org model policy and substitutes an allowed model if the frozen one was blocked.

**Spawning and linking (v1).** `MissionRunner.spawnWorker` calls the daemon's `spawnWorkerSession`:
cwd = mission working directory, `Auto` mode, `AutonomyLevel.High`, `autoRejectPermissionRequests`,
10 minute inactivity timeout, tags `exec`, `mission-worker`, and `mission-session` with
`{role, missionId}` where `missionId` is the orchestrator's session id
(`cli/services/daemon/TuiDaemonAdapter.ts`, `common/session/tags/constants.ts`). Legacy fields
`decompSessionType` / `decompMissionId` are deprecated in favour of tags. Each attempt's session id
is appended to the feature's `workerSessionIds`.

**v2** (`MissionV2SessionKind`, `sdk/session/tags/enums.ts`): `orchestrator` and `agent`. The
orchestrator gets `SpawnAgent`, `ListAgents`, `SendMessage`, `InterruptAgent`
(`packages/droid-core/src/tools/definitions/mission-v2/`); agents get `SendMessage` to the
orchestrator only. Agents run in plain `Auto` mode inheriting the orchestrator's autonomy (clamped to
the org max) and auto-reject flag. No model is passed, so agents use the target machine's default
(inferred from `cli/tools/executors/client/mission-v2/spawn-agent.ts`). Each carries a `mission-v2`
tag (`kind`, `missionId` = orchestrator session id, optional `orchestratorComputerId`, `templateId`)
and `callingSessionId` = orchestrator.

---

## 4. Decomposition and assignment

**Shapes (v1).** `MissionFeatureSchema` (`sdk/droid/schemas/mission-decomposition.ts`): `id`,
`description`, `status` (`pending | in_progress | completed | cancelled`), `skillName`,
`preconditions[]`, `expectedBehavior[]`, `fulfills[]` (assertion IDs), `milestone`, and
system-managed `workerSessionIds[]`. Three levels: **milestones** (agreed with the user, each ends in
validation and then closes to additions), **features** (one worker session each), and
**assertions** in `validation-contract.md` (stable IDs like `VAL-AUTH-001`, each naming a test tool
and required evidence). Invariant: every assertion is claimed by exactly one feature's `fulfills`.
The contract is written before the features ("mission-level TDD").

**Assignment is positional.** The queue is array order in `features.json`. The runner takes the first
`pending` feature, marks it `in_progress`, records the session, and injects the feature JSON into the
worker's bootstrap message (`getWorkerBootstrapPrompt`, `cli/services/mission/prompts.ts`). Finished
features move to the bottom. There are no explicit dependencies: order plus free-text
`preconditions` is the whole model. Urgent work is "insert at top"; if a worker is paused, that
preempts it (its feature is requeued and later restarted fresh).

**No parallelism across features in v1.** The runner is sequential, one worker at a time, all in one
working tree (no branches, no worktrees). Parallelism exists only inside sessions: orchestrator
research subagents, one scrutiny review subagent per feature, and user-testing "flow validator"
subagents sized to a measured resource budget (planning skill: 70 percent of free headroom).

**Worker procedure.** Skill `mission-worker-base`: read mission files in one parallel batch, run
`init.sh`, manage services only through `services.yaml`, never kill user processes, do the work per
the type skill, run validators, commit, clean up, call `EndFeatureRun`, stop.

**Handoff.** `EndFeatureRun` (`cli/tools/executors/client/mission/end-feature-run.ts`):
`successState` (`success | partial | failure`), `returnToOrchestrator`, `commitId` + `repoPath`
(required for code changes), `validatorsPassed` (must be true for success), and `handoff`:
`salientSummary` (1 to 4 sentences), `whatWasImplemented`, `whatWasLeftUndone`,
`verification.commandsRun[]` (command, exit code, observation), `interactiveChecks[]`, `tests`
(files, cases, coverage), `discoveredIssues[]` (severity `blocking | non_blocking | suggestion`), and
optional `skillFeedback` (followed the procedure? deviations, suggested changes). Calls from a
session that is not the active worker are refused. Effects in order: feature to `completed` or back
to `pending`; write `handoffs/<iso>__<feature>__<session>.json`; store a tool-call skeleton for
reviewers; set `orchestrator_turn` if needed; append `worker_completed` last, since it is the
completion signal. Workers never mark the mission complete; only the runner does.

**Milestone validation is system-driven.** When a milestone's implementation features are done, the
runner inserts `scrutiny-validator-<m>` and `user-testing-validator-<m>` at the queue top and logs
`milestone_validation_triggered` as an idempotency marker. It re-sweeps every milestone at the top
of each loop iteration, so an edge missed by a crash or pause still fires on resume. Scrutiny runs
test/typecheck/lint, reviews each feature via subagents, applies factual fixes to `services.yaml` and
`library/`, and recommends `AGENTS.md` and skill changes. User testing picks testable assertions
from `fulfills`, sets up services and data, runs flow validators, and updates
`validation-state.json`. Both always return to the orchestrator; each can be skipped in settings.

**Handoff gate.** `StartMissionRun` refuses to resume when the latest handoff lists issues or
unfinished work and, since then, there is neither a `DismissHandoffItems` record nor a relevant
mission file change. Dismissals take a type (`discovered_issue`, `critical_context`,
`incomplete_work`) and a 20+ character justification citing a feature ID.

**v2** is conversational: the orchestrator picks areas, calls `SpawnAgent({title, prompt,
target?})` per area, keeps session ids, and reuses agents via `SendMessage`. Agents are prompted to
report what changed, where, how it was verified, and what remains; nothing is schema-enforced.
Agents can create Software Factory workstreams for the mission, which are auto-announced to the
orchestrator (`announceCreatedMissionWorkstream`, `cli/services/mission-v2/messages.ts`).

---

## 5. Artifacts

"Artifact" means three things:

- **Mission artifact files** (v1): the mission directory (section 6), summarized by
  `rt/mission/src/missionArtifactMetadata.ts` into `FactoryMissionArtifactMetadata`
  (`common/session/schema.ts`): `state`, `title` (first `#` heading of `mission.md`),
  `workingDirectory`, `createdAt`, `updatedAt`, `elapsedMs`, `completedFeatures`, `totalFeatures`.
  Cloud-synced (coalesced to once a second, consent-gated) so the web list shows local missions.
- **Session artifacts**: external resources a session touched (`sdk/session/artifacts/schema.ts`):
  `id`, `url`, `title`, `externalId` (`owner/repo#123`, `FAC-123`), `provider` (`github | gitlab |
  linear | jira | notion | web`), `kind` (`pull_request | issue | document | link`), `action`
  (`create | update | delete | view | close | merge`, strongest wins), `source` (`tool | classifier
  | user_message`), `createdAt`, `toolCallId`. `fe/missions/MissionArtifactsPanel.tsx` renders the
  orchestrator's list in the generic `SessionArtifactsPanel`; mission PRs derive from these.
- **Shared files** (v2): a per-mission context space synced across machines. Agents see a read-only
  local mirror refreshed before every model request and write through `droid space doc edit|write`
  with optimistic concurrency (`--expected-version`); transcripts can be published into the space so
  agents can read each other (`cli/services/space-sync/guidance.ts`). Shown in the Files pane
  (`fe/missions/MissionFilesExplorer.tsx`: tree, list or grid, search, kind filter, deleted files).

---

## 6. Mission files, protection and validation

**Location:** `~/.factory/missions/<orchestratorSessionId>/` (`~/.factory-dev/` in dev;
`cli/utils/getMissionsDir.ts`). `state.json` also holds a different `missionId` (`mis_xxxxxxxx`)
used for telemetry, which is confusing.

System-managed (`cli/services/mission/MissionFileService.ts`, `schemas.ts`):

- `state.json`: `missionId`, `state`, `workingDirectory`, timestamps, `lastReviewedHandoffCount`,
  `initialFeatureCount` (scope baseline), `featureRetryBudgetBonus`, `artifactLayoutVersion`.
- `progress_log.jsonl`: the append-only event log, source of truth for worker state, timing, pause
  reasons, and idempotency markers.
- `model-settings.json`: worker and validator models plus skip flags, frozen at acceptance so later
  default changes cannot swap models under a running mission.
- `runtime-custom-models.json` (refreshed before each spawn), `working_directory.txt`, `mission.md`
  (the accepted proposal), `handoffs/*.json`, `handoffs.jsonl`, `worker-transcripts.jsonl`, and
  `canonical-artifact-layout.json` (migration marker for old missions that kept files in the repo's
  `.factory/`).

Orchestrator-authored: `features.json`, `architecture.md`, `validation-contract.md`,
`validation-state.json` (`{assertions: {ID: {status}}}`, all must pass to finish), `AGENTS.md`
(boundaries such as port ranges and off-limits services, directives, testing guidance),
`services.yaml` (commands and services with start, stop, healthcheck, port, depends_on; the single
source of truth for running things), `init.sh` (idempotent setup), `skills/<type>/SKILL.md`,
`library/*.md` (flat worker knowledge base), `research/`, `contract-work/`, and validator output in
`validation/<milestone>/{scrutiny,user-testing}/synthesis.json`. Outside the mission:
`~/.factory/state/mission-readiness-warnings-shown.json`.

**Protection** (`cli/utils/missionFileProtection.ts`, applied by
`cli/tools/executors/client/utils/protectedWritePath.ts` in Create, Edit, ApplyPatch):

- `state.json`, `progress_log.jsonl`, `model-settings.json` under the missions dir are blocked for
  every LLM session; only `MissionFileService` writes them.
- `features.json` is also blocked for worker and validator sessions (the plan is the
  orchestrator's; workers report through `EndFeatureRun`). Role comes from session tags captured at
  launch, not ambient state.
- Paths are checked as given and after symlink resolution; unresolvable symlink chains are refused.
- Only file tools are guarded. I found no equivalent check on shell writes through Execute.

**Validation** (`cli/utils/missionFileValidation.ts`): file-tool writes to `features.json`,
`state.json`, `runtime-custom-models.json`, or `handoffs/*.json` must parse and pass the on-disk Zod
schema, else the write is rejected with an LLM-facing message: up to eight issues, a valid example,
allowed enum values. Cosmetic slips are normalized first (bare-array features wrapped, numeric
`milestone` stringified). `StartMissionRun` also checks each `skillName` resolves to exactly one
`skills/<name>/SKILL.md` (`missionSkillValidation.ts`). Separately, Execute refuses
`droid exec ... --mission`, so agents cannot launch missions through a shell.

---

## 7. Readiness warnings

Evaluated before the session is converted (`cli/services/missionReadinessGate.ts`,
`utils/agentReadiness/utils.ts`; desktop calls daemon RPC `inspectMissionReadiness`):

- **Access first.** `assertMissionEntryAllowed` blocks during an active `/migrate`, when the org
  restricted missions to an allowlist, or when no overage preference is set or verifiable. Desktop
  shows `MissionEntryBlockModal` with "Set overage preference".
- **Gate.** `MissionReadinessGateState`: `ok | no_git | no_remote | no_report | low_score`. Empty
  folders are always ok; otherwise it needs a git repo with an `origin` remote and a backend "agent
  readiness report" at level 4 of 5 or above. The report fetch times out at 5 seconds and any
  failure degrades to ok, so detection problems never block or falsely warn.
- **Display.** Inside the onboarding modal: "Repository not agent-ready", state-specific copy (gist:
  missions need strong built-in validation; proceeding means you vouch for it), and actions: proceed
  anyway, run a readiness report, fix readiness signals, cancel. Cancel leaves the session untouched
  because conversion happens after the gate. Acknowledging stores the canonical folder, so it shows
  once per folder.

The orchestrator also runs its own **readiness check** before proposing: subagents verify each
dependency and the validation toolchain actually work and measure machine resources to set test
concurrency; the proposal must include a readiness section.

---

## 8. Team changes

"Team" in Factory's UI means **organization team attribution**, not the agent roster:
`ChangeMissionTeamDialog.tsx` edits `teamId` on the v2 orchestrator tag (also chosen in
`NewMissionDialog`), used for grouping and analytics.

- **v1** has a fixed shape: one orchestrator, one worker at a time, validators auto-injected.
  "Reassignment" is editing `features.json` (reorder, change `skillName`, cancel, add), restarting
  the in-progress feature (`restartFeature`), or preempting it. Worker and validator models can be
  changed per mission (sidebar or TUI Models view) only while paused; otherwise "Mission settings are
  locked after proposal approval". The attempt budget replaces stuck workers automatically.
- **v2** agents are added only by the orchestrator's `SpawnAgent`; the UI shows optimistic
  pending-spawn rows ("Setting up a computer", "Starting") parsed from tool calls
  (`fe/missions/spawnActivity.ts`). I found no user add, remove, or kill action: agents keep their
  session (and template computer) for the mission. `InterruptAgent` stops a turn, `SendMessage`
  redirects. Machines are fixed at start from the user's defaults; template computer teardown is not
  visible client-side (ambiguous, likely backend).

---

## 9. Mission Control information design

**List.** Desktop `fe/missions/MissionControlPage.tsx`: description, "New Mission", filter chips All
/ Running / Paused / Completed ("Running" = any non-terminal, non-paused state), columns Title,
Repository, Computer, Progress (completed of total features), Created, infinite scroll merging
local daemons and cloud metadata across machines, per-filter empty states. TUI
`cli/components/MissionsList.tsx` adds State, Updated, Session ID, Path, Features, V1/V2 tabs,
type-to-filter, Ctrl+R rename, "Exit current mission", and remote machines.

**v1 mission view** (orchestrator session plus mission sidebar):

- Header (`MissionHeader.tsx`, `missionHeaderData.ts`): mission mark, title, state, progress bar,
  Time (active, average per milestone, average per feature), Usage (credits, 5-hour usage percent,
  reset time), Pause or Resume ("Resuming" spinner), "Disconnected".
- Sessions sidebar (`sidebar/MissionSessionsSidebar.tsx`): Orchestrator first, then workers and
  validators under "Milestone n: title", filter All / Workers / Validators, "Awaiting your input".
- Features grouped by milestone with status Completed / In progress / Not started / Cancelled;
  detail shows description, preconditions, expected behavior, fulfills, milestone.
- Progress log rows ("Worker #3 completed [feature]", model substitutions, failure reasons) and a
  Models section (orchestrator, worker, validator).
- Worker activity from `MissionWorkerActivityPhase` (`idle | waiting_for_model |
  receiving_model_output | running_tool | waiting_for_approval | compacting`), "Delayed" after 90
  seconds waiting on the model (`utils/mission/workerSessions.ts`).
- Composer rules (`missionChatState.ts`): orchestrator composer disabled while running ("Pause to
  send messages"); a finished worker's composer points back to the orchestrator.
- The StartMissionRun tool card shows a live snapshot (counts, previous / current / next feature,
  worker activity) and error styling for auto-pauses.

**TUI Mission Control** (Ctrl+T, `cli/components/mission-control/`): framed overlay with views
`main | features | workers | mission_models | feature_detail | handoff_viewer | session_viewer`. Main
shows the active feature, features list, paged progress log, and active-worker preview. Keys F, W, M,
P (pause), R (resume), Tab, Ctrl+T (back). Header: credits, rate-limit usage, mission path, cwd.

**v2 mission view** (`fe/sessions/workspace/SessionWorkspace.tsx`, `fe/missions/`):

- Main column: orchestrator chat ("Message the mission lead..."), opening with a welcome block
  explaining agents, where work runs, shared files, PRs, and steering.
- Right pane launcher: Agents, Files, Terminal (mission computer shell), PRs, Workstreams, Browser
  (mission sites and previews), Analytics (credit spend by workstream and agent).
- Agents pane (`MissionAgentsPanel.tsx`): search, "show workstream sessions" filter, collapsible
  groups **Waiting on you / Working / Idle** (idle filterable by last-activity window), rows with
  title, activity label (attention summary, computer status, or latest activity with a shimmer), PR
  chip, keyboard navigation. Selecting opens the agent chat ("Message this agent...").
- Tabs with peek for agent, session, PR, task, workstream, and file (`tabs/missionTabIds.ts`).
- **Attention cards** (`MissionAgentAttentionCard.tsx`): above the orchestrator composer when any
  agent waits on the user. Oldest waiting agent's name, a summary ("Needs approval to run Execute
  and 2 more tools", "Has 2 questions for you"), an "N waiting" pill, one action: "View Agent".
  Kinds are `permission` and `ask-user` only (`MissionAgentAttentionKind`); permission outranks.

**Inbox** (`packages/daemon-core/src/attention/AttentionProducer.ts`): the daemon publishes
`mission_attention` (awaiting input; paused for usage exhausted, retries exhausted, scope growth)
and `mission_completion`. User pauses publish nothing.

---

## 10. PRs from missions

v1 never creates branches or PRs. Workers commit straight onto the mission working directory and
report `commitId` + `repoPath`; the orchestrator is told never to commit leftover worker changes.

The PRs view (`fe/pull-requests/missionPullRequests.ts`, `fe/missions/useMissionPullRequests.ts`) is
derived purely from session artifacts:

- Collect `pull_request` artifacts with action create, update, close, or merge from the orchestrator
  and every listed agent; dedupe by normalized URL, keep the newest title and the strongest terminal
  action (merge over close).
- Enrich with live provider metadata (state, draft, title, opened and updated times), falling back
  to the artifact's last action; mark "status pending" while loading. Poll open PRs and badge changes.
- Group Open, Draft, Closed, Merged; sort by last update, then number. Row menu: open in new tab,
  open on provider, copy link. Share links add `?pr=<path>`. Agent rows show "#123 +2".

So PRs exist only when agents open them (as instructed per mission); there is no mission-level branch
strategy.

---

## 11. Steering and intervention

**v1:**

- **Pause:** header Pause interrupts the orchestrator; the aborted `StartMissionRun` pauses the
  runner, which interrupts the worker, logs `worker_paused` then `mission_paused`, and sets
  `paused` with the feature left `in_progress`. Also TUI P, Ctrl+C, and CLI exit
  (`gracefulMissionExit`).
- **Talk:** only while paused or in an orchestrator turn. The orchestrator follows a mid-mission
  request procedure: clarify, propose, confirm, update every shared file stating the old truth
  (`mission.md`, `architecture.md`, `AGENTS.md`, `library/`, skills), delegate contract edits to a
  subagent, reconcile `fulfills` coverage, resume.
- **Resume:** the Resume button sends the literal user message `[resume the mission]`; the
  orchestrator calls `StartMissionRun`, which by default resumes the paused worker's session with a
  "continue where you left off, check git status first" reminder. Options: `messageToWorker` (the
  only way to tell a resumed worker about changes, since workers read shared state once at start),
  `restartFeature`, or preemption by inserting at the top.
- **Approve:** the proposal and orchestrator permission prompts. A "N other missions running, start
  anyway?" confirmation type exists, but `shouldConfirmExecution` returns false for StartMissionRun,
  so whether it is raised is unclear.
- **Cancel:** individual features (kept as `cancelled`) or exit the mission. Any worker transcript
  and handoff can be opened from the sidebar or TUI.

**v2:** the user can message the orchestrator or any agent at any time; a message steers a running
session or starts a turn on an idle one. Peer messages carry a `sender` rendered as
`[From orchestrator]` or `[From agent "title"]`; unheaded means human. The orchestrator uses
`InterruptAgent` and `SendMessage`. Approvals and questions are answered in the agent's view.
`runMissionTool` enforces that only the orchestrator spawns, lists, or interrupts, and that agents
message only their own orchestrator.

---

## 12. Failure and budget handling

- **Attempt budget:** 5 worker attempts per feature (`MAX_FEATURE_ATTEMPTS`). Exhaustion pauses with
  `feature_retry_limit_exceeded`, feature left `pending`; resume grants +5 (`featureRetryBudgetBonus`).
- **Scope breaker:** if implementation features exceed 4x the first-run count with at least 25 added,
  the run pauses with `scope_growth_limit_exceeded` and the orchestrator gets a bounded review
  prompt: explain the growth, judge viability, recommend reduce, split, continue, or end, then ask.
- **Credits (`cli/utils/signalUnrecoverable402ToMission.ts`):** on a 402 the agent loop first tries
  swapping eligible model slots to free "Droid Core" models if the overage preference allows (never
  for enterprise per-user caps). If that fails in a worker, it appends `worker_failed` with
  `failureReason: unrecoverable_usage_402` before rethrowing. The runner reads that marker from the
  log and pauses with `unrecoverable_usage_402` instead of requeuing into a respawn loop. UI: "Usage
  limit reached. Top up credits or change overage preference, then resume."
- **Exited without handoff** (`worker_exited_without_handoff`, written by the worker): requeue and
  return to the orchestrator, tracked apart from crashes.
- **Crashes, daemon errors, silence:** the daemon reaps a worker idle for 10 minutes
  (`MISSION_WORKER_INACTIVITY_TIMEOUT_MS`); a stall watchdog trips 5 minutes later if the worker
  never produced any signal after start or resume (laptop-sleep wedge). Each logs `worker_failed`,
  requeues, and hands control to the orchestrator. Partial or failed handoffs reset the feature to
  `pending` so it reruns first.
- **Orphans:** on start the runner closes any worker still recorded in progress and requeues it.
- **Model policy drift:** substitute an allowed model, or fail the spawn with a reason rather than
  burn attempts.
- **Liveness:** heartbeat notification every 3 minutes; optional wake lock (`caffeinate`,
  `systemd-inhibit`, `SetThreadExecutionState`) via `keepSystemAwakeDuringMissions`.
- **No spend cap.** Cost control is the overage preference, credits, retry budget, scope breaker,
  and onboarding warnings; spend is displayed (credits, 5-hour usage, v2 analytics).
- **v2:** delivery redials a dropped machine up to 3 times with jittered backoff but never resends
  the message (it may have landed); a spawn whose opening prompt failed tells the model to use
  `SendMessage` instead of spawning a duplicate; template provisioning times out.

---

## 13. Permissions and autonomy

- `AutonomyLevel` (`sdk/shared/enums.ts`): `off` (confirm all), `low` (edits and read-only
  commands), `medium` (reversible commands), `high` (all commands). Orgs can cap the maximum.
- **v1 orchestrator:** Mission mode gets high-autonomy guidance. The enum calls it read-only, but its
  tool set only adds orchestrator tools; "do not implement" is a prompt. Headless
  `droid exec --mission` requires `--auto high` or `--skip-permissions-unsafe`.
- **v1 workers:** `high` plus `autoRejectPermissionRequests`: anything still needing approval (say an
  org-denied command) is rejected, not prompted, since nobody is watching. No AskUser. Boundaries in
  `AGENTS.md` are prompt-level ("return to the orchestrator if you can't comply"). Writes are fenced
  by the file protections and the sandbox (the working directory must sit inside the writable
  boundary because workers treat it as their writable root).
- **Routing:** v1 approvals land in the orchestrator chat. v2 approvals stay on the agent and surface
  as attention (pane grouping, attention card, and `waitingOn` in `ListAgents` so the orchestrator
  knows not to resend).
- **Org controls:** mission access allowlist, org default models per role, model policy at spawn, max
  autonomy.

---

## 14. Settings

Desktop `fe/settings/missions/`, CLI `/settings` and Mission Control:

- **Missions version:** V1 or V2.
- **V1** (local settings; web shows a "use the desktop app" notice): orchestrator, worker, and
  validator model with reasoning level each; skip scrutiny; skip user testing (experimental in the
  TUI). Per-mission overrides live in `model-settings.json` (tagged "[mission]"), editable while
  paused.
- **V2** (cloud, per user per org, `UserMissionDefaultSettingsSchema`, `common/api/user/schemas.ts`):
  remote delegation on or off (off keeps every agent on the orchestrator's machine); default
  environment (template plus a required description the orchestrator reads to route work, fresh
  computer per agent); additional machines (Droid Computers, Remote Control computers, or templates,
  each described, deduped); orchestrator compaction budget in tokens, read live by running
  orchestrators. Save and Discard.
- **Other:** `keepSystemAwakeDuringMissions`, `hasSeenMissionOnboarding`, the readiness-ack store,
  enterprise mission access, org mission role model defaults.

---

## 15. Onboarding and entry points

- **CLI:** `/missions` lists v1 and v2 missions for this or a remote machine, with "Begin new
  mission" (v1) and "New Mission" (v2, flag and policy gated). The composer mode label becomes
  "Mission" or "Mission 2.0" ("Mission control for huge projects"). `droid exec --mission` runs
  headless with worker and validator model overrides and rejects spec mode, `--session-id`, forks,
  and streaming input.
- **New v1 mission** (`handleNewMission`, `cli/app.tsx`): access check, readiness evaluation, then if
  first time or gate not ok the onboarding modal: how it works (describe goal, approve plan, features
  run autonomously, validation at milestones), key concepts (orchestrator, workers, milestones),
  warnings (not for simple tasks, runs for hours or days, much higher credit use). Continue converts
  the session; Escape leaves it alone. Desktop Mission mode runs the same gate
  (`useMissionReadinessGate.ts`).
- **Desktop v2:** a 4-card welcome (hand off a project, a lead and its team, works while you're away,
  you lead rather than operate) and `NewMissionDialog`: name (required, capped), objective,
  orchestrator machine (local, a computer, or a template provisioned first), working directory on
  that machine, agent machines summary, team. It can enable Remote Control so remote agents can
  reach the orchestrator, and falls back to "agents run on the orchestrator machine" with a specific
  reason when policy, sync settings, or defaults rule out multi-machine.
- Script tool programs cannot call ProposeMission or the v2 mission tools; they stay top-level
  (`cli/repl/bridge.ts`, `cli/utils/toolAvailability.ts`).

---

## 16. What's worth taking, what's not

**Strong ideas:**

1. **A deterministic runner owns the loop.** v1's `MissionRunner` picks work, spawns, watches,
   requeues, and transitions from files; the LLM plans and triages. This maps directly onto Native's
   durable host.
2. **Append-only event log as truth**, with idempotency markers and level-triggered sweeps instead of
   one-shot edges. Write the completion event last so readers never see half-done state.
3. **Structured, evidence-bearing handoffs** (commands with exit codes and observations, interactive
   checks, tests, issues with severity, unfinished work, procedure feedback) plus a gate: no resume
   until each issue is scheduled or dismissed with a justification.
4. **A validation contract** with stable assertion IDs and exactly one owning feature each, written
   before the feature list, and validators injected by the system at milestone boundaries.
5. **Cross-provider validation**: implement on one vendor, validate and orchestrate on another.
   Native can make this a first-class default (Claude Code builds, Codex reviews, or the reverse).
6. **Circuit breakers with structured pause reasons** (attempt budget, scope growth, credits), each
   with its own copy, notification, and a clear "resume grants more" path.
7. **Role-scoped write protection and schema validation at write time**, with LLM-actionable errors
   and cosmetic normalization.
8. **A readiness gate** before a days-long autonomous run, acknowledged once per folder, never
   blocking on detection failure.
9. **An explicit channel to a resumed agent** (`messageToWorker`): long-lived agents do not reread
   shared state on their own.
10. **v2's crew UX**: Waiting on you / Working / Idle grouping, an attention card above the lead's
    composer, sender headers on peer messages, role-checked coordination tools, PRs aggregated from
    every session's artifacts.
11. **Freeze model choices at launch** and log any substitution.

**Weak or Factory-specific:**

- v1 runs one worker at a time in one working tree with no dependency graph: slow, and conflict
  handling never had to exist. Parallel features in worktrees with explicit `dependsOn`, integrated
  at milestone boundaries where validators run, would be better.
- The queue is a JSON file the LLM edits by hand, needing a validation layer to survive. Typed tools
  (add, reorder, cancel, update) are safer and give better errors.
- `StartMissionRun` is a blocking tool call: the orchestrator's turn stays open for hours and the user
  must pause everything to talk. A host-owned runner that posts events to an idle lead is cleaner.
- Heavy reliance on prompt text (thousands of words of orchestrator prompt and skills); key rules
  like "the orchestrator does not code" are unenforced.
- Billing coupling (overage preference, Droid Core swap, backend readiness reports, credits), cloud
  computers, Software Factory workstreams, two generations behind flags, two mission ids, a dead
  "manually edit" option.
- v2 drops what made v1 trustworthy: no mission state or pause, no structured handoffs, no
  validation, no retry budgets. A nicer chat surface over a weaker engine.

**Lessons for Native (ACP agents, local MCP server, worktrees, durable host):**

- Put the runner, event log, and mission store in the host (UI-free packages) so missions keep
  running when the window closes; Factory pauses on CLI exit because its runner lives in the client.
  Reconcile orphaned workers on host restart, hold a wake lock while running, heartbeat.
- Expose coordination as MCP tools on Native's local server: a handoff tool, messaging, roster,
  interrupt, queue edits. MCP works the same for Claude Code, Codex, and Cursor, and the server can
  enforce lead vs worker rules per ACP session the way `runMissionTool` does.
- Map roles to agent plugin plus model, not model alone. Per-role defaults in settings, frozen per
  mission, editable only while paused.
- Treat "ended the turn without calling the handoff tool" as its own outcome and resume that session
  once before spawning fresh; ACP turn completion gives the signal cleanly.
- Fold ACP permission requests from unattended agents into one attention model (permission vs
  question) shown as grouped crew state and a card on the lead's composer, and decide per role
  whether to auto-reject (v1 workers) or escalate (v2 agents).
- Give each assignment or agent its own worktree and branch, record commit and branch in the handoff,
  and make PR granularity a mission setting rather than an agent whim, while still deriving the PR
  list from what agents actually created.
- Keep Factory's honesty about failure: structured pause reasons, never a silent retry loop, every
  paused state saying what happened and what resume will do.
