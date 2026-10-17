# Factory Missions: how they work

Research notes for designing Native's own long-horizon multi-agent feature. Source is the read-only
rebuild at `~/developer/reverse/factory/factory-clone`. Path shorthands used below:

- `cli/` = `apps/cli/src/` (the `droid` CLI and the agent runtime the desktop app also drives)
- `fe/` = `packages/frontend/src/` (desktop and web UI)
- `sdk/` = `packages/droid-sdk-core/src/protocol/` (wire types and enums)
- `common/` = `packages/common/src/`, `utils/` = `packages/utils/src/`, `rt/` = `packages/runtime/`

**Two generations coexist.** Most of the machinery belongs to **Missions 1.0** (internally "mission
decomposition": an orchestrator plus a deterministic runner that feeds one worker at a time from a
feature queue, with auto-injected validators). **Missions 2.0** (feature flag `MissionsV2`, tag
`mission-v2`) is a much thinner, message-based design: an orchestrator spawns long-lived agents on
local or cloud machines and talks to them with `SendMessage`. Users pick a version in settings
(`fe/settings/missions/MissionVersionSelector.tsx`) and the `/missions` list shows both. Where this
document says "v1" or "v2" it means these two.

Note: `fe/app/MissionControlOverlay.tsx` has nothing to do with missions. It watches for macOS
Mission Control (the OS window overview, detected via a JXA poll of Dock windows in
`apps/desktop/src/main/windows/missionControl.ts`) and overlays the session title. The missions
Mission Control lives in `fe/missions/` (desktop) and `cli/components/mission-control/` (TUI).

---

## 1. What a mission is

A mission is a long-running, multi-session project ("hours or days", per onboarding copy) that an
orchestrator plans with the user, gets approved as a written proposal, and then executes by
delegating to other agent sessions, with progress persisted outside any single conversation so it
survives pauses, crashes, and app restarts. In v1 the plan is materialized as files (a feature queue,
a validation contract, worker skills, an environment manifest) and a non-LLM runner drives execution;
in v2 the plan lives in the orchestrator's head plus a shared document space, and execution is a
team of persistent agents that report back by message.

How it differs from neighbours:

- **Single agent session:** one transcript, one context window, the user drives turn by turn. A
  mission has a dedicated orchestrator session (session type upgraded to `orchestrator`,
  `DroidInteractionMode.Mission`) whose job is to not write code itself (enforced by repeated system
  reminders in `cli/core/AgentLoop.ts`, not by tool removal; see section 13).
- **Subagent (Task tool):** a child that runs inside the parent's turn and returns a result. Mission
  workers are independent top-level sessions (tagged `exec` + `mission-worker`), spawned through the
  daemon, with their own transcripts, resumable after a pause, and they hand off through a
  structured tool, not a return value. Both orchestrators and validators still use Task subagents
  internally for research, reviews, and parallel test flows.
- **Spec mode:** `DroidInteractionMode.Spec` is a read-only planning pass that ends with
  `ExitSpecMode` and then the same session implements. A mission proposal reuses the spec-review UI
  (`fe/missions/MissionSpecReviewPanel.tsx`, `SpecReviewKind.Mission`, downloads as
  `mission-proposal.md`) but approval creates a mission directory and kicks off artifact authoring
  and delegated execution instead of in-session implementation.

---

## 2. Lifecycle (v1)

`MissionState` in `sdk/droid/enums.ts`, persisted in `state.json`:

| State | Meaning | Written by |
| --- | --- | --- |
| `planning` | Orchestrator is planning with the user; no run yet | `MissionFileService.ensurePlanningState` on the first user turn of an orchestrator session (`cli/core/AgentLoop.ts`) |
| `awaiting_input` | Idle, waiting on the user | Interrupt during planning (`missionRunnerOperations.ts`), or `withMissionAwaitingUserInput` while an orchestrator turn blocks on AskUser or a permission prompt |
| `initializing` | Documented as "creating artifacts after acceptance" | Only written when `start-mission-run.ts` finds no state file. In practice acceptance leaves the state at `planning` until the run starts, so this looks vestigial (ambiguous) |
| `running` | Runner is spawning and monitoring workers; orchestrator chat is disabled | `StartMissionRun` executor |
| `paused` | Resumable stop | User pause, abort of the blocking tool call, CLI exit, or an auto-pause (below) |
| `orchestrator_turn` | A worker returned control or failed; the orchestrator acts next | `EndFeatureRun` (on `returnToOrchestrator`, partial or failure) and the runner (on failures, empty queue with incomplete work) |
| `completed` | Every feature completed or cancelled. Terminal | Runner when the queue drains, or `completeMissionAtOrchestratorTurnEnd` when the orchestrator ends a turn with everything done |

There are no `failed` or `cancelled` mission states. Failure is modeled as pauses with a structured
`MissionPauseReason` (`unrecoverable_usage_402`, `feature_retry_limit_exceeded`,
`scope_growth_limit_exceeded`; absent means user or runner pause), and features (not missions) can be
`cancelled`. A mission is abandoned by exiting it (`handleExitMission` in `cli/app.tsx`: graceful
pause, then downgrade the session back to a normal one).

Flow and triggers:

1. **Entry.** User runs `/missions` -> "Begin new mission", or picks Mission mode in the desktop
   composer, or `droid exec --mission`. Access check, readiness gate, onboarding (sections 7, 15),
   then `enterMissionMode()` (`cli/services/mission/enterMissionMode.ts`) upgrades the session.
2. **Planning.** Orchestrator invokes built-in skills `mission-planning` and `define-mission-skills`
   (`cli/skills/builtin/builtinSkillDefinitions.ts`), interviews the user, researches via
   subagents, verifies dependencies and the validation toolchain, and gets explicit user sign-off on
   infrastructure, testing strategy, and milestones.
3. **Proposal.** `ProposeMission` (requires confirmation). Choices: proceed, proceed with a comment
   (passed back as `llmGuidance`), or reject with an explanation. A "Manually edit mission" string
   and an `isEdited` result field exist, but `MissionProposalAction` only has
   `approve | approve-with-comment | reject` (likely dead). On accept the executor creates the
   mission dir, writes `working_directory.txt`, `mission.md`, a frozen model-settings snapshot, and
   logs `mission_accepted`. In headless exec there is no confirmation and it auto-approves.
4. **Artifact authoring.** A system reminder lists the files to write; orchestrator writes them.
5. **Run.** `StartMissionRun` validates preconditions, sets `running`, logs `mission_run_started`,
   then blocks while `MissionRunner` loops. It returns when a handoff needs attention
   (`orchestrator_turn`), on pause, or on completion, with handoff summaries.
6. **Orchestrator turn.** Orchestrator triages handoffs, edits `features.json` or dismisses items,
   calls `StartMissionRun` again. Repeat until `completed`.

Every transition is also an append to `progress_log.jsonl` (`ProgressLogEntryType`): `mission_accepted`,
`mission_paused` (+`pauseReason`), `mission_resumed` (+`resumeWorkerSessionId`),
`mission_run_started`, `worker_started` (+model, +`substitutedFromModelId`),
`worker_selected_feature`, `worker_completed` (+full handoff), `worker_failed` (+`failureReason`),
`worker_paused`, `handoff_items_dismissed`, `milestone_validation_triggered`. Active time is derived
from run-start/resume to pause intervals in this log (`utils/mission/missionElapsedTime.ts`).

**v2 has no mission state machine.** Each session is just idle/pending/running
(`DroidExecutionStatus`) with an optional attention (`permission` or `ask-user`). The mission exists
as long as its orchestrator session exists; there is no completed or paused state for the mission
as a whole that I could find.

---

## 3. Agent roles

`DecompSessionType` (`sdk/droid/enums.ts`) has exactly two values:

- **`orchestrator`**: the user-facing session. Plans, writes mission artifacts, triages handoffs,
  talks to the user. Tools added: `ProposeMission`, `StartMissionRun`, `DismissHandoffItems`
  (`ORCHESTRATOR_TOOL_IDS` in `cli/agent/tools.ts`).
- **`worker`**: one feature per session. Gets `EndFeatureRun`; loses orchestrator tools, AskUser,
  ProposeWorkstream, settings staging, and TodoWrite (`WORKER_FORBIDDEN_TOOL_IDS`,
  `isUnattendedSession` in `cli/utils/toolAvailability.ts`).

**Validators are workers**, distinguished only by the feature's `skillName`
(`scrutiny-validator` or `user-testing-validator`, `VALIDATION_SKILL_NAMES`). The UI labels them
"Validator #n" and workers "Worker #n" (`fe/missions/missionSessionTags.ts`,
`missionSessionsSidebar.*` strings). Worker types beyond that are mission-authored skills (for
example `backend-worker`), each a `skills/<type>/SKILL.md` in the mission dir.

**Models.** Three role slots: orchestrator, worker, validation worker, each with model plus
reasoning effort (`MissionModelSettingsSchema` in `sdk/settings/schema.ts`; orchestrator model is a
general setting). Code constants in `utils/llm/constants.ts` make the out-of-box intent visible:
feature workers on a Claude Opus model, validators and the orchestrator on a GPT model, orchestrator
at high reasoning. Implementers and validators deliberately run on different providers. If the
user's current model is on `MISSION_ORCHESTRATOR_RECOMMENDED_MODELS` it is kept (effort bumped to at
least high); otherwise the configured orchestrator model is swapped in. When nothing is stored, the
settings service falls back to the general default model, so which default actually wins is
ambiguous. The runner re-checks org model policy on every spawn and substitutes an allowed model if
the frozen one became blocked, recording the substitution in the progress log.

**Spawning and linking (v1).** `MissionRunner.spawnWorker` calls the daemon's
`spawnWorkerSession` with cwd = mission working directory, `Auto` mode, `AutonomyLevel.High`,
`autoRejectPermissionRequests: true`, a 10 minute inactivity timeout, and tags `exec`,
`mission-worker` plus a `mission-session` tag carrying `{role, missionId}` where `missionId` is the
orchestrator's session id (`cli/services/daemon/TuiDaemonAdapter.ts`,
`common/session/tags/constants.ts`). Older fields `decompSessionType` / `decompMissionId` are
deprecated in favour of tags. The feature records each attempt's session in `workerSessionIds`.

**v2 roles** (`MissionV2SessionKind` in `sdk/session/tags/enums.ts`): `orchestrator` and `agent`.
The orchestrator gets `SpawnAgent`, `ListAgents`, `SendMessage`, `InterruptAgent`
(`packages/droid-core/src/tools/definitions/mission-v2/`). Agents get `SendMessage` (orchestrator
only). Agents run in plain `Auto` mode, inheriting the orchestrator's autonomy (clamped to org max)
and auto-reject flag; no per-role model is passed, so agents use the target machine's default model
(inferred from `cli/tools/executors/client/mission-v2/spawn-agent.ts`). Each agent carries a
`mission-v2` tag with `kind`, `missionId` (orchestrator session id), optional
`orchestratorComputerId` and `templateId`, plus `callingSessionId` = orchestrator.

---

## 4. Decomposition and assignment

**Data shapes (v1).** `MissionFeatureSchema` (`sdk/droid/schemas/mission-decomposition.ts`):
`id`, `description`, `status` (`pending | in_progress | completed | cancelled`), `skillName`,
`preconditions[]`, `expectedBehavior[]`, `fulfills[]` (validation assertion IDs), `milestone`,
system-managed `workerSessionIds[]`. Three levels: **milestones** (agreed with the user; each ends in
validation and is then closed to additions), **features** (one worker session each), and
**assertions** in `validation-contract.md` (stable IDs like `VAL-AUTH-001`, each with a tool and
evidence requirements). Invariant: every assertion is claimed by exactly one leaf feature's
`fulfills`. The orchestrator authors the contract first ("mission-level TDD"), then features.

**Assignment is positional.** The queue is simply array order in `features.json`: the runner picks
the first `pending` feature, marks it `in_progress`, appends the new session id, and injects the
feature JSON into the worker's bootstrap message (`getWorkerBootstrapPrompt` in
`cli/services/mission/prompts.ts`). Completed features move to the bottom; stranded done features
get re-sorted (`moveStrandedDoneFeaturesToBottom`). There are no explicit dependencies: ordering
plus free-text `preconditions` is the whole dependency model. Urgent work is "insert at top"; if
that happens while a worker is paused, the runner preempts it (requeues the in-progress feature and
later restarts it fresh).

**Parallelism: none across features in v1.** `MissionRunner` is a sequential loop, one worker at a
time, all in the same working tree (no branches, no worktrees). Parallelism only exists inside
sessions: the orchestrator's research and contract subagents, scrutiny review subagents (one per
feature), and user-testing "flow validator" subagents partitioned by a measured resource budget
(planning skill: 70 percent of free RAM/CPU headroom).

**Worker procedure.** Base skill `mission-worker-base`: read mission files in one parallel batch, run
`init.sh`, start services strictly via `services.yaml`, never kill user processes, do the work per
the type skill, run validators, commit, clean up, then call `EndFeatureRun` and stop.

**Handoff.** `EndFeatureRun` (`cli/tools/executors/client/mission/end-feature-run.ts`) takes
`successState` (`success | partial | failure`), `returnToOrchestrator`, `commitId` + `repoPath`
(required for code changes on success), `validatorsPassed` (must be true for success), and a
`handoff`: `salientSummary` (1 to 4 sentences), `whatWasImplemented` (min 50 chars),
`whatWasLeftUndone`, `verification.commandsRun[]` (command, exit code, observation),
`interactiveChecks[]` (action, observed), `tests` (files and cases added, coverage summary),
`discoveredIssues[]` (severity `blocking | non_blocking | suggestion`, suggested fix), and optional
`skillFeedback` (did you follow the procedure, deviations, suggested skill changes). It refuses calls
from a session that is not the active worker. Effects, in order: feature to `completed` or back to
`pending`, write `handoffs/<iso>__<feature>__<session>.json`, append a transcript skeleton for
reviewers, set `orchestrator_turn` if needed, and only then append `worker_completed` (the
completion signal) so readers never act on half-written state. Workers never mark the mission
complete; the runner is the single authority.

**Milestone validation is system-driven.** When a milestone's implementation features are all done,
the runner inserts `scrutiny-validator-<m>` then `user-testing-validator-<m>` at the top of the
queue and logs `milestone_validation_triggered` as an idempotency marker. It re-sweeps all milestones
at the top of every loop iteration, so a missed edge (crash, pause race) still fires on resume.
Scrutiny runs test/typecheck/lint, reviews each feature with subagents, applies factual fixes to
`services.yaml` and `library/`, and recommends `AGENTS.md`/skill changes. User testing derives
testable assertions from `fulfills`, sets up services and data, runs flow validators, and updates
`validation-state.json`. Both always return to the orchestrator. Either can be skipped by setting.

**Orchestrator gate on handoffs.** `StartMissionRun` refuses to resume if the latest handoff has
discovered issues or unfinished work and, since then, neither a `DismissHandoffItems` record nor a
relevant mission-file change exists. Dismissals need a typed reason (`discovered_issue`,
`critical_context`, `incomplete_work`) and a 20+ character justification citing a feature ID.

**v2 decomposition** is entirely conversational: the orchestrator decides areas, `SpawnAgent({title,
prompt, target?})` per area, keeps session ids, and reuses agents via `SendMessage`. Agents report
"what changed, where, how verified, what remains" by message, prompted but not schema-enforced.
Agents can create Software Factory workstreams tied to the mission; a successful
`droid sf db-create-workstream` is auto-announced to the orchestrator
(`announceCreatedMissionWorkstream` in `cli/services/mission-v2/messages.ts`).

---

## 5. Artifacts

Three different things are called artifacts:

- **Mission artifact files** (v1): everything in the mission directory (section 6). Read by
  `rt/mission/src/missionArtifactMetadata.ts` into `FactoryMissionArtifactMetadata`
  (`common/session/schema.ts`): `state`, `title` (first `#` heading of `mission.md`),
  `workingDirectory`, `createdAt`, `updatedAt`, `elapsedMs`, `completedFeatures`, `totalFeatures`.
  This summary is cloud-synced (coalesced to once per second, consent-gated) so the web list can
  show local missions.
- **Session artifacts**: external things a session touched, recorded per session
  (`sdk/session/artifacts/schema.ts`). Fields: `id` (stable identity), `url`, `title`,
  `externalId` (`owner/repo#123`, `FAC-123`), `provider` (`github | gitlab | linear | jira | notion |
  web`), `kind` (`pull_request | issue | document | link`), `action` (`create | update | delete |
  view | close | merge`, merged by strength), `source` (`tool | classifier | user_message`),
  `createdAt`, `toolCallId`. `fe/missions/MissionArtifactsPanel.tsx` just renders the orchestrator
  session's list in the generic `SessionArtifactsPanel`; mission PRs are derived from these
  (section 10).
- **Shared files** (v2): a per-mission "context space" synced across machines. Agents see a
  read-only local mirror refreshed before every model request and write via
  `droid space doc edit|write` with optimistic concurrency (`--expected-version`); session
  transcripts can be published into the space so agents can read each other
  (`cli/services/space-sync/guidance.ts`). Surfaced in the Files pane
  (`fe/missions/MissionFilesExplorer.tsx`: tree, list/grid, search, kind filter, deleted-file view).

Also `cli/utils/artifactsProtection.ts` guards a separate system "artifacts directory" for
generated outputs (not mission-specific).

---

## 6. Mission files, protection and validation

**Location:** `~/.factory/missions/<orchestratorSessionId>/` (`~/.factory-dev/` in dev builds;
`cli/utils/getMissionsDir.ts`). Confusingly `state.json` also holds a separate `missionId` like
`mis_xxxxxxxx` used for telemetry.

System-managed:

- `state.json`: `missionId`, `state`, `workingDirectory`, `createdAt`, `updatedAt`,
  `lastReviewedHandoffCount`, `initialFeatureCount` (scope baseline), `featureRetryBudgetBonus`,
  `artifactLayoutVersion` (`cli/services/mission/schemas.ts`, `types.ts`).
- `progress_log.jsonl`: append-only event log (section 2). The primary source of truth for worker
  state, timing, pause reasons, and idempotency markers.
- `model-settings.json`: frozen worker/validator model snapshot plus skip flags, taken at proposal
  acceptance so later default changes cannot swap models under a running mission.
- `runtime-custom-models.json`: custom-model registry refreshed before each spawn and handed to workers.
- `working_directory.txt`, `mission.md` (the accepted proposal), `handoffs/*.json`, `handoffs.jsonl`,
  `worker-transcripts.jsonl` (tool-call skeletons for reviewers), `canonical-artifact-layout.json`
  (migration marker for older missions that kept files in the repo's `.factory/`).

Orchestrator-authored: `features.json`, `architecture.md`, `validation-contract.md`,
`validation-state.json` (`{assertions: {ID: {status}}}`; end-of-mission gate is all passed),
`AGENTS.md` (boundaries such as port ranges and off-limits services, directives, testing guidance),
`services.yaml` (named commands and services with start/stop/healthcheck/port/depends_on; the single
source of truth for how to run things), `init.sh` (idempotent setup), `skills/<type>/SKILL.md`,
`library/*.md` (flat worker knowledge base), `research/`, `contract-work/`, and validator output
under `validation/<milestone>/{scrutiny,user-testing}/synthesis.json`.

Outside the mission: `~/.factory/state/mission-readiness-warnings-shown.json` (section 7).

**Protection** (`cli/utils/missionFileProtection.ts`, wired through
`cli/tools/executors/client/utils/protectedWritePath.ts` into Create, Edit, and ApplyPatch):

- `state.json`, `progress_log.jsonl`, `model-settings.json` inside the missions dir are blocked for
  every LLM session. Only `MissionFileService` writes them.
- `features.json` is additionally blocked for worker and validator sessions (the plan belongs to the
  orchestrator; workers report via `EndFeatureRun`). Identity comes from the session tags captured
  at launch, not ambient state.
- Paths are checked both as given and after symlink resolution (realpath, with `/var` vs
  `/private/var` handled); unresolvable symlink chains are refused.
- These guards cover file tools only. I found no equivalent check on shell writes through Execute.

**Validation** (`cli/utils/missionFileValidation.ts`): any file-tool write to `features.json`,
`state.json`, `runtime-custom-models.json`, or `handoffs/*.json` must parse as JSON and pass the
on-disk Zod schema, otherwise the write is rejected with an LLM-facing message listing up to eight
issues, a copy-pasteable valid example, and allowed enum values. Cosmetic slips are normalized first
(bare-array `features.json` wrapped, numeric `milestone` coerced to string). Zod messages are
redacted from telemetry. `StartMissionRun` separately validates that every `skillName` resolves to
exactly one `skills/<name>/SKILL.md` (`missionSkillValidation.ts`) and that features exist.

Also: the Execute tool refuses `droid exec ... --mission` so an agent cannot launch a mission
through a shell, and tells the user the official entry points for their surface.

---

## 7. Readiness warnings

Checked before the session is converted into a mission (`cli/services/missionReadinessGate.ts`,
`utils/agentReadiness/utils.ts`, daemon RPC `inspectMissionReadiness` for desktop):

- Policy first: `assertMissionEntryAllowed` blocks when a `/migrate` run is active, when the org
  restricted missions to an allowlist the user is not on, or when no overage preference is set
  (or could not be verified). Desktop shows `MissionEntryBlockModal` with "Set overage preference".
- Then `MissionReadinessGateState`: `ok | no_git | no_remote | no_report | low_score`. Empty
  directories are always ok. Otherwise it needs a git repo with an `origin` remote and a backend
  "agent readiness report" at level 4 of 5 or higher. Report fetch has a 5 second timeout and any
  failure degrades to ok so detection problems never block or falsely warn.
- Shown inside the onboarding modal: "Repository not agent-ready" with state-specific copy (the
  gist: missions need strong built-in validation; proceeding means you vouch for it). Actions:
  proceed anyway, run a readiness report, fix readiness signals (runs `/readiness-report` or
  `/readiness-fix`), cancel. Cancelling leaves the session untouched because conversion happens
  only after the gate.
- Acknowledging persists the canonical folder path, so the warning shows once per folder.

Separately, the orchestrator runs its own **Mission Readiness Check** phase before proposing:
delegated subagents verify every dependency and the validation toolchain actually work and measure
machine resources to set concurrency limits; the proposal must include a "Mission Readiness"
section.

---

## 8. Team changes

"Team" in Factory's UI means **organization team attribution**, not the agent roster.
`ChangeMissionTeamDialog.tsx` edits `teamId` on the v2 orchestrator tag (chosen in
`NewMissionDialog`, "The team this mission is attributed to"), used for grouping and analytics.

Changing the agent roster:

- **v1** has a fixed shape: one orchestrator, one worker at a time, validators auto-injected. You
  "reassign" by editing `features.json` (reorder, change `skillName`, cancel, add), restarting the
  in-progress feature (`restartFeature`), or preempting it by inserting work at the top. Worker and
  validator models can be changed per mission in the sidebar or the TUI Models view, but only while
  paused ("Mission settings are locked after proposal approval" otherwise). Each feature has an
  attempt budget, so a stuck worker is replaced by a fresh one automatically (section 12).
- **v2** agents are added only by the orchestrator's `SpawnAgent`; the UI shows optimistic "pending
  spawn" rows ("Setting up a computer", "Starting") derived from tool calls
  (`fe/missions/spawnActivity.ts`). I found no user-facing add, remove, or kill action: agents keep
  their session (and template computer) for the rest of the mission. `InterruptAgent` stops a turn;
  redirecting is `SendMessage`. Machines are fixed at mission start (from the user's defaults);
  how template computers are torn down is not visible client-side (ambiguous, likely backend).

---

## 9. Mission Control information design

**Mission list** (desktop `fe/missions/MissionControlPage.tsx`; TUI `cli/components/MissionsList.tsx`).
Desktop: header with description and "New Mission"; filter chips All / Running / Paused / Completed
("Running" means any non-terminal, non-paused state); table columns Title, Repository, Computer,
Progress (completed of total features), Created; infinite scroll merging local daemon lists and
cloud-synced metadata across machines; per-filter empty states. TUI adds State, Updated, Session ID,
Path, Features, version tabs (V1/V2), type-to-filter, Ctrl+R rename, "Exit current mission", and
remote-machine listings.

**v1 mission view** (orchestrator session with a mission sidebar):

- Header (`MissionHeader.tsx`, `missionHeaderData.ts`): "MISSION" mark, title, state, progress bar,
  Time (tooltip: active time, average per milestone, average per feature), Usage (tooltip:
  Factory Standard Credits, 5-hour usage percent, reset time), Pause or Resume (or "Resuming"
  spinner), "Disconnected".
- Sessions sidebar (`sidebar/MissionSessionsSidebar.tsx`): Orchestrator first, then workers and
  validators grouped under "Milestone n: title" headings, filter All / Workers / Validators, an
  "Awaiting your input" marker, live activity per worker.
- Features section: grouped by milestone; status indicator Completed / In progress / Not started /
  Cancelled; feature detail shows description, preconditions, expected behavior, fulfills, milestone.
- Progress log section: human-readable event rows ("Worker #3 completed [feature]", model
  substitution notes, failures with reasons).
- Models section: orchestrator, worker, validator model rows.
- Worker activity line from `MissionWorkerActivityPhase` (`idle | waiting_for_model |
  receiving_model_output | running_tool | waiting_for_approval | compacting`), with "Delayed" after
  90 seconds of waiting on the model (`utils/mission/workerSessions.ts`).
- Composer rules (`missionChatState.ts`): orchestrator composer disabled while running ("Pause to
  send messages"); a finished worker's composer says to return to the orchestrator.
- The StartMissionRun tool card renders a live progress snapshot (state, counts, previous / current
  / next feature window, worker activity) and error styling for auto-pauses.

**TUI Mission Control** (Ctrl+T, `cli/components/mission-control/`): framed full-screen overlay with
views `main | features | workers | mission_models | feature_detail | handoff_viewer |
session_viewer`. Main shows active feature (skill, milestone, preconditions, expected behavior),
features list, paged progress log, and an active-worker preview. Keys: F, W, M, P pause, R resume,
Tab, Ctrl+T back. Header shows credits, rate-limit usage, mission path, and working dir.

**v2 mission view** (`fe/sessions/workspace/SessionWorkspace.tsx`, `fe/missions/`):

- Main column: the orchestrator chat ("Message the mission lead..."), opening with a welcome block
  explaining agents, where work runs, shared files, PRs, and steering.
- Right pane launcher (`rightPaneV2Launcher.*`): Agents, Files, Terminal (shell on the mission
  computer), PRs, Workstreams, Browser (mission sites and previews), Analytics (credit spend by
  workstream and agent).
- Agents pane (`MissionAgentsPanel.tsx`): search, optional "show workstream sessions" filter,
  collapsible groups **Waiting on you / Working / Idle** (idle filterable by last-activity window),
  rows with title, activity label (attention summary, computer status, latest activity with a
  shimmer while working), PR summary chip, keyboard navigation. Selecting opens the agent's chat
  ("Message this agent..."), with "Back to mission".
- Tabs with peek for agent, session, PR, task, workstream, and file (`tabs/missionTabIds.ts`).
- **Attention cards** (`MissionAgentAttentionCard.tsx`): pinned above the orchestrator composer
  when any agent waits on the user. Shows the oldest waiting agent's name, a summary ("Needs
  approval to run Execute and 2 more tools" or "Has 2 questions for you"), an "N waiting" pill, and
  one action, "View Agent". Kinds are only `permission` and `ask-user`
  (`MissionAgentAttentionKind`); permission outranks question.

**Notifications/inbox** (`packages/daemon-core/src/attention/AttentionProducer.ts`): the daemon
publishes `mission_attention` (awaiting input; paused with reason usage exhausted, worker retries
exhausted, scope growth) and `mission_completion`. User-initiated pauses publish nothing.

---

## 10. PRs from missions

v1 never creates branches or PRs. Workers commit straight onto the mission working directory and
report `commitId` + `repoPath`; the orchestrator is told never to commit leftover worker changes.

The PRs view (`fe/pull-requests/missionPullRequests.ts`, `fe/missions/useMissionPullRequests.ts`) is
purely derived from session artifacts:

- Collect `pull_request` artifacts with action create, update, close, or merge from the orchestrator
  session and every listed agent session; dedupe by normalized URL, keeping the newest title and the
  strongest terminal action (merge over close).
- Enrich with live provider metadata (state, draft, title, opened and updated times); fall back to
  the artifact's last action when metadata is missing; flag "status pending" while loading.
- Poll for changes on open PRs and badge changed rows until viewed.
- Group Open, Draft, Closed, Merged; sort by last update, then PR number.
- Row menu: open in new tab, open on provider, copy link. Share links add `?pr=<path>` to the
  mission share URL. Agent rows show a compact "#123 +2" summary.

So the PR flow depends on agents opening PRs themselves (instructed per mission), not on any
mission-level branch strategy.

---

## 11. Steering and intervention

**v1:**

- **Pause:** header Pause interrupts the orchestrator session; the aborted `StartMissionRun` pauses
  the runner (`pauseMissionRunner`), which interrupts the worker, logs `worker_paused` then
  `mission_paused`, and sets `paused`. The feature stays `in_progress`. Also via P in TUI, Ctrl+C
  (SIGINT, CLI-owned processes only), and on CLI exit (`gracefulMissionExit`).
- **Talk:** only while paused or in an orchestrator turn. The orchestrator follows a "mid-mission
  request" procedure: clarify, propose, get confirmation, update every shared file that states the
  old truth (`mission.md`, `architecture.md`, `AGENTS.md`, `library/`, skills), delegate contract
  edits to a subagent, reconcile `fulfills` coverage, then resume.
- **Resume:** Resume button sends the literal user message `[resume the mission]`; the orchestrator
  calls `StartMissionRun`, which by default resumes the paused worker's session with a "continue
  where you left off, check git status first" reminder. Options: `messageToWorker` (the only way
  to tell a resumed worker about changes, since workers read shared state only at start),
  `restartFeature` (fresh worker), or preemption by inserting a feature at the top.
- **Approve:** the proposal; permission prompts in the orchestrator; a mission-level
  `start_mission_run` confirmation type exists for "N other missions running, start anyway?", but
  the CLI's `shouldConfirmExecution` returns false for StartMissionRun, so whether it is raised is
  unclear.
- **Cancel:** cancel individual features (kept, status `cancelled`) or exit the mission.
- Users can open and read any worker transcript and handoff from the sidebar or TUI.

**v2:** the user can message the orchestrator or any agent at any time. Messages to a running
session steer it mid-turn; to an idle one they start a turn. Peer messages carry a `sender`
(`MessageSenderSchema`) rendered as `[From orchestrator]` or `[From agent "title"]`; unheaded
messages are the human. The orchestrator interrupts with `InterruptAgent` and redirects with
`SendMessage`. Approvals and questions are answered in the agent's view. Tool-level enforcement
(`runMissionTool`): only the orchestrator may spawn, list, or interrupt; agents may only message
their own orchestrator.

---

## 12. Failure and budget handling

- **Per-feature attempt budget:** 5 worker attempts (`MAX_FEATURE_ATTEMPTS`). On exhaustion the
  mission pauses with `feature_retry_limit_exceeded` and the feature stays `pending`; resuming grants
  +5 more for that feature (`featureRetryBudgetBonus`). UI: "Feature retry limit reached".
- **Scope-growth breaker:** if implementation features exceed 4x the count at first run and at least
  25 were added, the run pauses with `scope_growth_limit_exceeded` and the orchestrator gets a
  bounded review prompt: explain growth, judge viability, recommend reduce / split / continue / end,
  then AskUser.
- **Credits exhausted (`signalUnrecoverable402ToMission`, `cli/utils/`):** on a provider 402 the
  agent loop first tries swapping eligible model slots to free "Droid Core" models if the org's
  overage preference is `droidCore` (never for enterprise per-user caps). If that fails and the
  session is a mission worker, it appends `worker_failed` with `failureReason:
  unrecoverable_usage_402` before rethrowing. The runner sees that marker (from the log, not from
  the exit) and pauses with `unrecoverable_usage_402` instead of requeuing into a tight respawn loop.
  UI: "Usage limit reached. Top up credits or change overage preference, then resume."
- **Worker exited without a handoff** (`worker_exited_without_handoff`, written by the worker
  itself): requeue, return to the orchestrator, distinct from a crash in metrics.
- **Crashes, daemon errors, inactivity:** daemon cleans up a worker silent for 10 minutes
  (`MISSION_WORKER_INACTIVITY_TIMEOUT_MS` env override). A start/resume stall watchdog trips at that
  plus 5 minutes if the worker produced no signal at all (laptop-sleep wedge). Each logs
  `worker_failed`, requeues the feature, and hands control to the orchestrator.
- **Failed or partial handoffs** reset the feature to `pending`, so it reruns first after triage.
- **Orphans:** on start the runner closes any worker still recorded in progress and requeues it.
- **Model policy drift:** substitute an allowed model; if none, fail the spawn with a reason rather
  than burn attempts.
- **Liveness:** heartbeat notification every 3 minutes while waiting; optional wake lock
  (`caffeinate` / `systemd-inhibit` / `SetThreadExecutionState`) while a mission session runs
  (`keepSystemAwakeDuringMissions`).
- **Budgets:** there is no per-mission spend cap. Cost control is the overage preference, credits,
  the retry budget, the scope breaker, and onboarding warnings. Spend is displayed (credits, 5-hour
  usage, per-agent analytics in v2).
- **v2:** message delivery redials a dropped machine connection up to 3 times with jittered backoff
  but never resends the message itself (it may have landed); a spawn whose opening prompt failed
  tells the model to use `SendMessage` rather than spawn a duplicate; template provisioning has a
  timeout.

---

## 13. Permissions and autonomy

- Autonomy levels (`AutonomyLevel`, `sdk/shared/enums.ts`): `off` (confirm everything), `low` (file
  edits and read-only commands), `medium` (reversible commands), `high` (all commands). Org admins
  can cap the maximum.
- **v1 orchestrator:** Mission interaction mode gets high-autonomy guidance. The enum comment calls
  it read-only, but its tool set only adds orchestrator tools and removes worker ones; "do not
  implement code" is a per-turn system reminder, not a tool restriction. Headless
  `droid exec --mission` requires `--auto high` or `--skip-permissions-unsafe`.
- **v1 workers:** `Auto` + `high` with `autoRejectPermissionRequests`: anything still needing
  approval (for example org-denied commands) is rejected instead of prompting, because nobody is
  watching. No AskUser. They must stay inside `AGENTS.md` boundaries and return to the orchestrator
  when they cannot (prompt-level). Writes are fenced by the file protections above and the sandbox
  (the proposed working directory must be inside the writable boundary, since workers treat it as
  writable root).
- **Approvals route** to the orchestrator chat in v1. In v2 they stay on the agent session and
  surface as attention (agents pane grouping, attention card, `waitingOn` in `ListAgents` so the
  orchestrator knows not to resend instructions).
- **Org controls:** mission access policy with allowlist, org default models per mission role,
  model policy enforcement at spawn, max autonomy.

---

## 14. Settings

Desktop `fe/settings/missions/`, CLI `/settings` and Mission Control:

- **Missions version:** V1 or V2 segmented control.
- **V1 (local settings; web shows a notice to use the desktop app):** orchestrator model and
  reasoning level, worker model and reasoning level, validator model and reasoning level, skip
  scrutiny, skip user testing (both marked experimental in the TUI). Per-mission overrides live in
  the mission's `model-settings.json` (shown with a "[mission]" tag), editable only while paused.
- **V2 (cloud, per user per org, `UserMissionDefaultSettingsSchema` in `common/api/user/schemas.ts`):**
  remote delegation on or off ("off keeps every agent on the orchestrator's machine"); default
  environment (template plus a required description the orchestrator reads to route work; each agent
  gets a fresh computer); additional machines (Droid Computers, Remote Control computers, or
  templates, each with a description, deduped); orchestrator compaction budget in tokens, read live
  by running orchestrators. Unsaved changes have Save / Discard.
- **Other:** `keepSystemAwakeDuringMissions`, `hasSeenMissionOnboarding`, the readiness-ack store,
  enterprise mission access, org-wide mission role model defaults.

---

## 15. Onboarding and entry points

- **CLI:** `/missions` lists v1 and v2 missions for this machine (or a remote one), with
  "Begin new mission" (v1) and "New Mission" (v2, gated by flag and policy). Composer mode label
  becomes "Mission" or "Mission 2.0", placeholder "Mission control for huge projects", tips mention
  Ctrl+T and `/missions`. `droid exec --mission` runs headless with `--worker-model`,
  `--validator-model`, and reasoning overrides; it is incompatible with spec mode, `--session-id`,
  forks, and streaming input.
- **New v1 mission flow** (`handleNewMission` in `cli/app.tsx`): access check, readiness evaluation,
  then if first time or gate not ok show the onboarding modal ("How it works: describe goal, review
  and approve plan, droid executes features autonomously, validation at milestones"; key concepts
  orchestrator / workers / milestones; warnings: not for simple tasks, runs for hours or days, much
  higher credit usage). Continue converts the session; Escape leaves it untouched.
- **Desktop v1:** Mission mode in the new-session composer runs the same gate
  (`useMissionReadinessGate.ts`, "Checking mission readiness...").
- **Desktop v2:** a 4-card welcome dialog (hand off a project, a lead and its team, it works while
  you are away, you are the lead not the operator) and `NewMissionDialog`: mission name (required,
  length-capped), objective, orchestrator machine (local, a computer, or a template that is
  provisioned first), working directory picker on that machine, agent machines summary, team. It
  can turn on Remote Control so remote agents can reach the orchestrator, and degrades to
  "agents run on the orchestrator machine" with a specific reason when org policy, sync settings,
  or defaults prevent multi-machine.
- The proposal flow and resume flows are covered in sections 2 and 11. Script tool programs cannot
  call ProposeMission or the v2 mission tools; they stay top-level (`cli/repl/bridge.ts`,
  `cli/utils/toolAvailability.ts`).

---

## 16. What's worth taking, what's not

**Strong ideas:**

1. **A deterministic runner owns the loop, not an LLM.** v1's `MissionRunner` picks work, spawns,
   watches, requeues, and decides transitions from files. The LLM plans and triages. This is the
   single best idea and maps directly onto Native's durable host process.
2. **Append-only event log as truth**, with idempotency markers and level-triggered sweeps (milestone
   validation re-checked every iteration) instead of fragile one-shot edges. Write the completion
   event last so readers never see half-done state.
3. **Structured handoffs with evidence**: commands run with exit codes and observations,
   interactive checks, tests added, issues with severity, unfinished work, procedure feedback. Plus
   the gate that the orchestrator cannot resume until each issue is scheduled or dismissed with a
   justification. This stops silent tech-debt loss.
4. **Validation contract with stable assertion IDs, one owning feature each**, written before the
   feature list, with system-injected validators at milestone boundaries that the planner cannot
   skip or fake.
5. **Cross-provider validation**: implementers on one vendor, validators and the orchestrator on
   another. Native can make this a first-class default (Claude Code builds, Codex validates, or the
   reverse) because it already speaks to several providers.
6. **Circuit breakers with structured pause reasons**: per-feature attempt budget, scope-growth
   breaker, credits exhausted. Each maps to specific copy, notification, and a clear "resume grants
   more budget" path.
7. **Role-scoped write protection plus schema validation at write time** with LLM-actionable errors
   (example payload, allowed values) and cosmetic normalization.
8. **Readiness gate**: refuse to start a days-long autonomous run silently on a repo with no way to
   validate work; acknowledge once per folder; never block on detection failure.
9. **Explicit resume channel** (`messageToWorker`): a resumed agent does not reread shared state.
   Any design with long-lived agents needs this.
10. **v2's agent UX**: roster grouped Waiting on you / Working / Idle, an attention card above the
    lead's composer, sender headers on peer messages, role-checked coordination tools, and PRs
    aggregated from every session's artifacts.
11. **Freeze model choices at launch** and record substitutions in the log.

**Weak or Factory-specific:**

- v1 runs one worker at a time in one working tree with no dependency graph. Slow, and it never
  exercised conflict handling. Native should parallelize independent features in worktrees with an
  explicit `dependsOn` and merge or integrate at milestone boundaries, where validators run.
- The queue is a JSON file the LLM edits by hand, needing a validation layer to survive. Typed MCP
  tools (add, reorder, cancel, update feature) are safer and give better errors.
- `StartMissionRun` is a blocking tool call: the orchestrator's turn stays open for hours and the
  user cannot talk to it without pausing everything. A host-owned runner that posts events to an
  idle orchestrator is cleaner.
- Huge reliance on prompt text (the orchestrator system prompt and skills are thousands of words);
  key rules like "orchestrator does not code" are not enforced.
- Billing coupling (overage preference, Droid Core swap, backend readiness reports, credits),
  cloud computers and templates, Software Factory workstreams, two generations behind flags, two
  different mission ids, and a dead "manually edit" option.
- v2 drops everything that made v1 trustworthy: no mission state, no pause, no structured handoffs,
  no validation, no retry budgets. It is a nicer chat surface over a weaker engine.

**Lessons for Native (ACP agents, local MCP server, worktrees, durable host):**

- Put the runner, event log, and mission store in the host process (Packages, no UI), so missions
  keep running when the window closes; Factory pauses on CLI exit because its runner lives in the
  client. Reconcile orphaned workers on host restart, keep a wake lock while running, heartbeat.
- Expose coordination as MCP tools on Native's local server (`end_feature_run`-style handoff,
  `send_message`, `list_agents`, `interrupt_agent`, feature-queue edits). MCP works across Claude
  Code, Codex, and Cursor alike, and the server can enforce role rules (worker vs lead) the way
  `runMissionTool` does, keyed by the ACP session id.
- Make roles map to agent plugins plus model, not just model. Per-role defaults in settings,
  frozen per mission, editable only while paused.
- Treat "agent ended its turn without calling the handoff tool" as its own outcome and resume that
  session once before spawning fresh; ACP turn completion gives the signal cleanly.
- Map ACP permission requests from unattended workers into one attention model (permission vs
  question), surfaced as grouped agent state and a card on the lead's composer. Decide per role
  whether to auto-reject (v1 workers) or escalate (v2 agents).
- Give each feature or agent its own worktree and branch, record commit and branch in the handoff,
  and decide PR granularity (per feature or per milestone) as a mission setting instead of leaving
  it to the agent. Derive the PR list from what agents actually created, like Factory does.
- Keep Factory's honesty about failure: structured pause reasons, never a silent retry loop, and
  every paused state telling the user what happened and what resume will do.
