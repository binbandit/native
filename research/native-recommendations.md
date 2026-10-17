# Recommendations for Native

Concrete changes for the Mac app, refined inside the Factory + Conductor direction. Each item names its
target, the evidence (see the per-app notes), and what to build. Ordered by impact on how Native feels
during real agent work. Native already does a lot of this well (queue/steer, exploration folding, one
approval card, exact limit wording, `DotGridLoader`, next steps, the product-quality rules); items below
either extend those or close gaps. Conflicts with the established direction are flagged **Conflict**.

## P0 - transcript and composer (felt every turn)

### 1. Name thinking by a fact: "Thought for 12s"
- **Target**: `Views/Transcript/MessageView.swift` (`ThoughtView`), `TranscriptStyle`.
- **Evidence**: v0 "Thought for 14s", Perplexity "2 steps completed", Claude's one-line work summary.
- **Build**: while reasoning streams, the row reads "Thinking" with a ticking seconds count in tertiary
  tabular figures; when it ends it freezes to "Thought for 12s". Same row height, same chevron, never
  auto-expanded. Agents that send no timing get the duration from first to last thought chunk.

### 2. A ticking clock on live work, a total on finished turns
- **Target**: `ToolCallView`'s `ToolRow` trailing slot; a turn footer in `SessionView`; a shared duration
  formatter in `DesignSystem` (add it to product-quality's "one formatter each" table).
- **Evidence**: Grok's "Searching ... 10s" live header and per-answer elapsed; Orca's "Working for" bar.
- **Build**: the running tool row shows elapsed seconds after 3s (before that it's noise). The turn's end
  gets a quiet footer: "1m 12s · 7 files changed +120 −14" (see 4). Product-quality already asks that a
  running agent "says what it's doing right now"; a clock is the cheapest proof it isn't stuck.

### 3. Collapse finished turns into one summary line
- **Target**: `ToolActivityGroupView` (extend the read/search folding to whole turns), `SessionView`.
- **Evidence**: Perplexity "N steps completed", Claude's work-summary sentence, Grok's narration with
  thoughts folded, v0's one-line rows.
- **Build**: the turn that is running stays fully expanded (Factory rows). Once a newer turn starts, an
  older turn's tool activity folds to one row: "Explored 6 files, edited 3, ran 4 commands", expandable.
  Agent prose and approvals never fold.
- **Conflict (mild)**: Factory keeps every row visible. Keep current behavior for the latest turn and make
  folding of older turns a View-menu toggle with the folded state as default; revisit after use.

### 4. Checkpoint card when a turn changed files
- **Target**: a new `TurnChangesCard` in the transcript, built on `DiffStatLabel`; opens the changes
  inspector (⌘⇧D); hosts the existing `composerNextSteps` (review, commit, PR).
- **Evidence**: v0's "v1 + summary + preview" followed by "25 files changed +2021".
- **Build**: after a turn that edited files: "7 files changed  +120 −14  ›" with Review / Commit as quiet
  buttons. It is also the payload for the "done" notification and the companion's task row.

### 5. Agent questions as a docked form
- **Target**: the one approval card (product-quality "something needs the user"), composer top section
  (next to `QueuedPromptsSection` / `ComposerPlanSection`), `docs/keyboard.md`.
- **Evidence**: Grok's question card (pager, lettered options with descriptions, "type your own",
  Skip/Next); v0's non-blocking "4 questions to answer" card that collapses to an answers summary.
- **Build**: when an agent asks structured questions (Claude Code's AskUserQuestion / ACP elicitation),
  show them in the composer's top section: question, `1/3` pager, options as rows with title + one line,
  a free-text row, Skip / Next. Afterwards the transcript keeps a compact key/value summary of answers.
- **Keyboard**: number keys pick options while the question card has focus (it takes focus when it
  appears and the composer is empty). **Conflict**: ⌘1-⌘9 is session navigation, so do not use ⌘-digits;
  plain digits only when focused, Tab moves between card and composer. Update `docs/keyboard.md` first.

### 6. Effort/model picker discloses cost at the point of choice
- **Target**: `ModelPicker`, `ModelPill`, `EffortBars`.
- **Evidence**: Claude's effort list ("Recommended", "5x or more usage" badge, footnote that higher effort
  uses limits faster); Perplexity's locks on unavailable modes.
- **Build**: each model row: name, one-line purpose, plan badge if gated. Effort levels: mark the agent's
  default "Recommended"; the top level carries a neutral badge with the relative cost the agent reports
  (or a plain "uses limits faster"). Unavailable models show a lock and the reason, not an error later.

### 7. Composer: keep send/stop in one spot, keep the field live
- **Target**: `ComposerActionButtons`, `ComposerView`.
- **Evidence**: every AI app (send, then stop, same place); Perplexity's live field while answering.
- **Build**: Native already swaps send and stop (Factory buttons) and queues while working. Check two
  details: the stop button must be exactly where send was (no width jump when the status line changes),
  and the placeholder should change while working to say what Return will do ("Queue a follow-up").

## P1 - lists, usage, notifications

### 8. Sidebar: a preview line for tasks that need you
- **Target**: `DesignSystem/Sidebar/TaskRow.swift`.
- **Evidence**: Orca worktree rows (status dot, branch, PR badge, last agent line), Spark previews.
- **Build**: keep Conductor's 36pt single-line row. Only for `needsAttention` statuses, add a second
  tertiary line with what is asked ("Allow `rm -rf build`?", "3 questions") so triage needs no click.
- **Conflict**: Conductor rows are strictly one line. This adds height only where action is pending;
  if that looks noisy, put the same text in the row's tooltip and the status bar instead.

### 9. Pinned and Active sections in the task list
- **Target**: `SidebarView`, `SessionOrdering`.
- **Evidence**: Orca's Pinned / Active sections; Claude's All / Pinned filter; Perplexity mode chips.
- **Build**: a Pin action (context menu, and the companion follows the same order). Pinned tasks sit in a
  small section above projects. A sidebar filter for "Needs you" is worth more than more sections.

### 10. Inline limit card in the transcript, plus a Usage page
- **Target**: `Usage/Views/LimitBanner.swift` (keep), a transcript card variant, a new Settings > Usage page.
- **Evidence**: Grok's in-transcript "you've hit your limit" card and Usage page (percent used, exact
  reset date and time, per-feature breakdown, extra credits); v0's "0.22 / 5, resets in 30 days"; Orca's
  per-account 5h and 7d bars.
- **Build**: when a turn stops on a limit, put the same `LimitBanner` content as a card at the point the
  work stopped (with Resume at Reset), so scrolling back explains the gap. Settings > Usage lists each
  provider account: each window's bar (`UsageMeter`), "Resets Fri 10:35 AM", and what used it (per task
  if the agent reports it). One wording everywhere, as product-quality already requires.

### 11. Notifications: only for long work and for "needs you", with actions
- **Target**: `Usage/System/UserNotificationAlerts.swift` (generalize beyond limits), Settings > Notifications, `Sounds`.
- **Evidence**: Grok's single "notify when a long-running task finishes" toggle; ChatGPT's "tell you
  when tasks are done"; Orca's finish/idle push with cross-device dismissal.
- **Build**: three triggers: a turn that ran longer than N seconds finished while Native wasn't frontmost
  (or the task wasn't visible); a permission request; a question. Permission notifications carry Allow /
  Reject actions (same as ⌘Y / ⌘⇧⌫); question notifications carry a text-reply action. Body uses the
  checkpoint summary ("Done in 4m · 7 files changed"). Sounds follow the same three triggers with one
  distinct sound for "needs you". Design the payloads now; the companion reuses them.

### 12. Settings: values in rows, consequences in toggles, extensions group
- **Target**: `Settings/Pages/*`, `SettingsRow`, `SettingsSwitch`.
- **Evidence**: Claude Capabilities (consequence copy, dependency explained), ChatGPT value-in-row, Grok's
  floating settings search, Flighty's "Extensions" group.
- **Build**: every toggle gets a one-line consequence ("When off, ..."); forced toggles say what forces
  them; selects show their current value at the row's trailing edge. When the companion ships, add
  "Paired devices" and "Notifications" under one group, with the device list from item 2 of the
  companion doc.

### 13. Empty states: two lines, one action, or the first step itself
- **Target**: `EmptyStateView` users (Home, PRs, Changes, Automation, Subagents).
- **Evidence**: convergent across all AI apps; Termius and ChatGPT Codex make the empty state the first step.
- **Build**: audit that every empty pane has a title, one "what will appear here" line, and one action.
  Where the action is a single input (e.g. a goal, a workflow name), put the input in the empty state.

## P2 - polish and smaller wins

14. **Tool row tense follows phase** (`ToolPresentation`): "Reading", "Editing" while running; "Read",
    "Edited" when done (verbs are base-form today: "Read", "Edit", "Write"). v0 and Factory both read as
    past-tense logs.
15. **Subagent count chip** at the end of a turn that spawned agents ("2 agents ›" opens the inspector,
    ⌥⌘I), each with its live activity line (Grok's "1 agent running" sheet). Target: `SubagentViews`.
16. **Plan's current item shows a live ring** (`PlanView` tints it today; use the `DotGridLoader` family or
    a dashed ring like v0) so the plan reads as progress at a glance.
17. **Follow-up suggestions as reply-arrow rows** under the last message for agents that offer them, and
    for `composerNextSteps` when they are prompts rather than actions (ChatGPT, Grok, Perplexity).
18. **Jump to latest**: a small circular button above the composer when scrolled up during a running turn
    (all apps). Check `SessionView`; add if missing.
19. **Failed send restores the draft** with a "Not sent" note (Orca 0.0.53); an interrupted turn is shown
    ended with the reason (product-quality already covers crash recovery; make the transcript say it).
20. **Home: a "Needs you" strip** above the agent cards when any task is waiting (Orca home's attention
    focus, Spark's buckets). Target: `Views/Home/HomeView.swift`.
21. **Status bar** (`StatusBar/Items/Tasks`): show working and needs-you counts with the longest-running
    task's elapsed time; clicking needs-you jumps to the oldest request (mirrors a Live Activity).

## Things we saw and should not adopt

- **Serif response text** (Claude): conflicts with Geist across Factory and Conductor; keep one family.
- **Black primary pills with no accent** (Claude/ChatGPT): Native's orange send button is part of
  Factory's identity; keep it, but keep accent usage as narrow as those apps (send, attention, selection).
- **Upsell cards on the home composer**: no business reason in Native; announcements (new agent support,
  update available) can use the same dismissible docked card instead.
- **Cards for every tool call**: every app with agentic work moved to single-line rows; Native already
  did, keep it.
