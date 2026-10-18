# Product quality

Good-looking screens are cheap now: every team and every agent can produce them. What makes a
product feel premium is evidence that it was thought through, and that evidence lives in three
places. Every feature in Native is reviewed against them. (Adapted from Tim Gabe, "The Psychology
of Premium Apps", 2026.)

## 1. Every state, not just the happy screen

AI-built interfaces tend to skip the unglamorous parts: showing what the system is doing, letting
people take something back, and getting them out of trouble. The user pays for that gap in doubt:
did it work, can I undo this, what now?

For every action in Native, the user always knows:

- **What just happened.** Every action gets visible feedback at the place it was taken. A queued
  message shows as queued; a steer says whether it joined the turn or was queued; a running agent
  says what it's doing right now, not just "Working…".
- **That they can take it back.** Prefer undo over confirmation. Renaming, archiving, removing a
  project, deleting a queued message and changing a setting can all be undone (⌘Z, or an undo
  toast). Destructive operations that can't be undone (discarding changes, removing a worktree)
  save a checkpoint first (`refs/native-checkpoints/*`) and say so.
- **What to do next.** When a turn ends, offer the next step (review the changes, commit, open a
  pull request). When nothing can happen yet, say why and what will change that.

Never show nothing. An empty list, an agent that isn't installed, a session without a context
breakdown, a project with no pull requests: each says what it is, why it's empty, and offers the
one action that fills it.

## 2. One product, not a collection of screens

People live in the whole product, where screen 80 sits next to screen 1. Inconsistencies cost them
far more than they report, and when agents can produce a screen a minute, it's easy to end up with
screens that don't agree. Every recurring situation has exactly one pattern, defined once in the
design system and used everywhere:

| Situation | The one pattern |
| --- | --- |
| Agent status (starting, ready, not installed, needs sign-in, stopped) | `AgentRuntimeStatus` label, severity and guidance, rendered by one status component everywhere: sidebar footer, status bar, settings, new-session menu |
| Task status (working, needs input, needs approval, done, failed) | `TaskStatus` + `StatusIndicator` |
| Something needs the user (tool permission, workflow step, plan) | One approval card; ⌘Y approves the oldest, ⌘⇧⌫ rejects |
| Usage limits | Exact numbers and an exact time, the same in the banner, notification, status bar and sidebar: which provider, which window, and when it resets ("Claude Code · 5-hour limit reached · resets 3:05 PM, in 42 min"), plus Resume at Reset / Snooze |
| Errors | What happened, what Native already did about it, what the user can do, and one primary action |
| Loading | One loader family (`DotGridLoader`), never ad-hoc spinners |
| Empty states | `EmptyStateView`: what this is, why it's empty, one action |
| A Settings row | The trailing edge says what it is: a control (`SettingsSwitch`, `SettingsSelect`, `.settingsField()`) is a setting; a verb button (`.buttonStyle(.settings)`) is an action; plain text (`SettingsValue`) is a value that can't change here; a lock badge and a dimmed control (`.settingsManaged(by:)`) means the organization decides. Anything else is information, in a `SettingsNote` card, never a row without a control |
| Searching or filtering a list | `SearchField` |
| Counts, sizes and times | One formatter each, in `DSFormat`: relative times, elapsed work time (`duration`: 8s, 1m 12s, 1h 4m, "Thought for 12s"; `ElapsedTimeText` ticks), token counts like 228k, diff stats like +12 −3, cost ($0.42), memory and CPU |

Before calling a feature done, use Native for an hour as a real user would and write down every
spot where it stops feeling like the same product.

## 3. Failure is where premium is proven

When a failure is handled well, people can end up happier than if nothing had gone wrong: the
product caught them. Native's worst moments, and what catching the user means in each:

| Failure | Caught means |
| --- | --- |
| An agent crashes mid-turn | Native restarts it, reloads the session, tells the agent it was interrupted, and tells the user it did so |
| A provider limit is hit | The exact reset time, one-click Resume at Reset, and the work resumes on its own |
| Sign-in expired or missing | An inline Sign in that runs the agent's own login, then continues what the user was doing |
| Offline or a provider outage | Say so plainly, keep the user's message queued, retry when the network returns |
| A CLI isn't installed | Exactly how to install it, then re-check without restarting Native |
| An MCP server fails | Which server, its error output, and Retry / Disable for this project |
| Push rejected, conflicts, checks failing | The reason in plain words and the next action (pull and retry, open the conflicts, view the failing check) |
| The context window is nearly full | Warn early with the breakdown and offer to compact or start a fresh task with a summary |
| The app quits or the Mac restarts | Work continues or resumes, and Native shows what happened while the user was away |

**Break it on purpose.** Every feature is tested with: the agent process killed mid-turn, Wi-Fi off
mid-turn, a sign-in revoked, a limit hit, an MCP server that fails to start, an empty project,
a missing CLI, and the host killed. These states get the same design care as the success path.
