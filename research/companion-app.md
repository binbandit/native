# iPhone companion: screen-by-screen proposal

Grounded in **Orca Mobile** (the primary reference: a well-reviewed phone remote for a desktop that runs
many coding agents in worktrees, see `companion/orca/screens.md`), the AI assistant apps (Claude,
ChatGPT's Codex hand-off, Grok, Perplexity, v0) and the pairing / Live Activity / notification references
in `companion/references.md`. Consistent with `docs/companion.md`: the phone is an ACP client of the
Mac's gateway, reuses `Packages/ACP` and the shared transcript views, pairs by QR on the same network
first, then Tailscale, then an end-to-end encrypted relay, and every paired device can be revoked.

## Principles

1. **The Mac is the source of truth; the phone is a window and a remote.** Like Orca, nothing runs on
   the phone, and when the Mac is unreachable the app says exactly why instead of spinning.
2. **The phone's job is attention.** It exists to answer "does anything need me, is it still going, is it
   done?" and to act in seconds: approve, answer, steer, queue, start. Reading a whole transcript is
   secondary, editing code is out of scope.
3. **Same meaning, same words.** `TaskStatus`, the approval card, limit wording, diff stats and duration
   formats are the Mac's, so a task looks the same on both devices (product-quality "one pattern").
4. **Native iOS chrome, Native's content.** Liquid Glass for navigation, toolbars and the composer only;
   transcript content uses the design system's tokens (Geist, neutrals, orange for send and "needs you").

## Information architecture

No tab bar. One stack:

```
Tasks (home)  ──>  Task  ──>  Tool / diff detail (sheet)
   │                 └──>  Question / approval (docked, or sheet)
   ├──>  New task (sheet)
   ├──>  Macs (sheet)  ──>  Mac detail
   └──>  Settings (sheet)
```

On iPad: a sidebar with the task list and the task on the right (Orca's iPad layout, Native's own
layout on the Mac).

---

## 1. First run and pairing

**References**: Orca (pair-scan, pair-confirm, notification-opt-in), Alfred (QR + expiry countdown),
OurPact (code fallback), Duet (say what to do on the computer), Teleprompter (transports with tradeoffs),
ChatGPT Codex ("connect your desktop app"), Termius (local discovery).

1. **Welcome** - one screen: app mark, one line ("Check on your agents and answer them from anywhere.
   Your Mac does the work."), primary "Pair with your Mac". No account, no carousel.
2. **Find your Mac** - if Bonjour sees Macs running Native, list them (Mac name, model glyph, "On this
   network"); otherwise a calm discovery state (Termius radar, one status line) and the instruction for
   the Mac side: "On your Mac, open Native ▸ Settings ▸ Devices ▸ Pair iPhone." Primary action: **Scan
   QR**; secondary: "Enter code instead".
3. **Scan** - camera in a rounded card (Authenticator), title "Scan the code on your Mac", paste/enter
   code fallback (Orca).
   - **Mac side** (Settings ▸ Devices): a sheet with the QR, a six-character code set wide (OurPact), and
     an expiry countdown (Alfred). The code is single use and expires in minutes (Orca).
4. **Confirm** - "Pair with Brayden's MacBook Pro?" with the Mac's name and model as the Mac reports it,
   and a short verification phrase shown on **both** devices (four words or a six-digit number) so the
   user can see they match before keys are exchanged. Pair / Cancel. The Mac shows the same sheet with
   the phone's name and the same phrase, and needs its own Allow.
5. **How to reach your Mac** - one screen, three rows with honest tradeoffs (Teleprompter):
   - Same network: fastest, works only at home or office.
   - Tailscale: anywhere your tailnet reaches, no Native server involved.
   - Relay: anywhere, zero setup; end-to-end encrypted, the relay only forwards ciphertext.
   Default to what's available; this becomes a row in Settings ▸ Macs later.
6. **Notifications** - priming screen with a realistic example on a lock-screen mockup (Windy, Open):
   "Claude Code needs approval · Run `pnpm test`?" with Allow / Reject visible. Copy: be told when an
   agent needs you or finishes long work. Then the system prompt; success shows a small "Notifications
   on" check pill (Pep). "Not now" is fine: the app works without them and Settings offers it again.
7. **Live Activity** (optional, iOS) - one education sheet with a lock-screen preview (Pacer), toggle on.

Errors here say what to do on the Mac: "Native isn't open on that Mac", "This code expired - make a new
one on your Mac", "Your Mac and iPhone aren't on the same network - try Tailscale or Relay". A "Pairing
log" disclosure under any failure (Orca) helps when it's genuinely broken.

## 2. Tasks (home)

**References**: Orca home and worktree list (Desktops card, Pinned / Active, status dot, branch, PR
badge, last agent line), Spark (time buckets, unread dot), Todoist (row density, sheet detail), Grok
drawer (two-line titles with time), Claude chats list (bottom search + floating "New" pill).

Layout, top to bottom:

- **Mac status capsule** (glass, under the large title "Tasks"): "MacBook Pro · Connected · 5 working".
  States: Connected (LAN / Tailscale / Relay named in small text), Reconnecting (with the attempt count),
  Mac asleep, Native closed on the Mac, Signed out / revoked (each with its one action). With several
  Macs it reads "2 Macs · 7 working" and opens the Macs sheet.
- **Needs you** section (only when non-empty), each row actionable without opening the task:
  - Permission: agent glyph, task title, the ask in one line ("Run `rm -rf dist`"), **Reject / Allow**
    buttons inline; long-press for Allow always and the full request.
  - Question: "3 questions" with Answer.
  - Plan review: "Plan ready for review" with Review.
- **Working** section: status (Native's working dot grid), title, second line "Editing `Composer.swift`"
  (the live tool row's text), elapsed time trailing ("4m"). Subagents roll up as "+2 agents".
- **Done** section bucketed Today / Yesterday / Earlier (Spark): title, outcome line ("7 files changed
  +120 −14", "Failed: tests", "Cancelled"), age. Unread = orange 6pt gutter dot (Factory/Spark).
- Bottom: search field and a floating **New task** pill (Claude, ChatGPT, v0 all put these at the bottom).
- Filters: a single menu (All / Needs you / Pinned, and by project or agent). Pinned order follows the Mac
  (Orca 0.0.53).

Row = Native's `TaskRow` content at iOS sizes: 44pt minimum, title in body, second line tertiary, status
glyph leading, trailing age or badge. Swipe right: Pin; swipe left: Archive (with undo toast, as on the
Mac). Pull to refresh only re-syncs; data is live over the gateway.

Usage lives here too, as a quiet footer card when any provider is past 80% or limited (Orca's
"Account usage" with 5h / 7d bars, Native's exact limit wording, Resume at Reset as the action).

## 3. Task

**References**: Native's own transcript (shared views), v0 (one-line tool rows, "Thought for Ns",
checkpoint "N files changed"), Grok (narration with folded thoughts, live step with seconds, subagent
sheet), Perplexity ("N steps completed", live field while answering), Orca (agent tab vs raw view,
"Working for" bar).

- **Header**: title (renamable), agent glyph + project + branch/worktree as a subtitle, status. Toolbar:
  Stop (while working), `...` menu (Pin, Rename, Open on Mac, Copy link, Archive).
- **Live bar** under the header while working (Orca's "Working for"): the current step and elapsed time,
  plus the plan's progress ("3 of 7") which expands into the checklist (v0 Tasks sheet, live ring).
- **Transcript** (shared `MessageView`, `ToolCallView`, `ToolActivityGroupView`, `DiffView`,
  `SubagentViews`, compiled for iOS):
  - Older turns folded to one summary line; the latest turn expanded (Mac recommendation 3).
  - Thinking as "Thought for 12s"; tool rows one line each; tap opens a sheet with the full command,
    output or diff (view-only, horizontally scrollable code, Copy).
  - Checkpoint card after file-changing turns: "7 files changed +120 −14 ›" opens a per-file diff list.
  - Subagents as a chip ("2 agents ›") opening a sheet with each agent's live line (Grok).
  - Limit card inline where the work stopped, with Resume at Reset.
  - Jump-to-latest circle when scrolled up.
- **Composer** (glass, bottom): text field, `+` (photos, files from the Mac's project via `@` mention,
  slash commands), a pill row for model / effort / autonomy (Orca's pill row), mic for dictation, and the
  primary button: send when idle, **Queue / Steer** while working (a two-segment control or a long-press on
  send, mirroring Return / ⌘Return on the Mac and the user's default), stop is in the toolbar so it can't
  be hit by accident while typing.
  - Quick replies above the field when the agent is idle after a question: "Continue", "Yes", and the
    agent's own suggested follow-ups as reply-arrow rows (Grok, ChatGPT, Perplexity).
  - Queued messages show as chips above the composer (same as the Mac), editable and removable.
  - Failed sends keep the text and say "Not sent" (Orca).
- **Raw view**: not a terminal (Native drives agents over ACP), but a "Show tool output" toggle in the
  `...` menu for people who want everything expanded.

## 4. Approvals

The one approval card from product-quality, sized for a thumb.

- **Where**: docked above the composer in the task, and inline in Tasks ▸ Needs you, and as a
  notification with actions, and on the Live Activity. All four resolve the same request; the first
  answer wins and the others update to "Allowed from iPhone" / "Rejected on Mac".
- **Content**: agent glyph and task; what exactly is asked (command in mono, file path, or a compact diff
  with +/− counts, "show full" opens the sheet); the agent's reason if it gave one (Orca 0.0.51: show what
  the agent actually asked for); options exactly as the agent offers them (Allow once, Allow always,
  Reject, Reject with feedback).
- **Safety**: Allow always and anything under bypass/full-access require Face ID when enabled in
  Settings. Destructive-looking commands (`rm`, `git push --force`, writes outside the worktree) get a
  neutral warning line, not a red wall.
- **Record**: the transcript on both devices logs "Allowed once from iPhone" (docs/companion.md).

## 5. Questions

Grok/v0's form, shared with the Mac (Mac recommendation 5): a card says "3 questions"; Answer opens a
sheet with one question per page, title, `1 of 3`, options with a line of description, Other (free text),
Skip / Next, Submit. Afterwards the transcript shows the answers as a compact key/value card.

## 6. Steer, queue and start

- **Steer / Queue**: as in the composer above; the hint text says which will happen ("Queues until this
  turn ends" / "Joins the running turn"), same wording as the Mac's status line.
- **New task** (sheet from the floating pill or a Shortcut): agent (cards like the Mac's Home, last-used
  first), project (recent projects on the chosen Mac), worktree toggle ("Run in its own worktree",
  default from the Mac's setting - this answers the open question in `docs/companion.md` by deferring to
  the Mac's default), prompt with dictation, Start. The task appears on the Mac without stealing focus
  (Orca), and the phone navigates into it.
- **Siri / Shortcuts / Share sheet** (later): "Ask Claude Code on my Mac to ..." creates a task the same way.

## 7. Notifications

**References**: Grok (notify only for long work), ChatGPT ("tell you when tasks are done"), Orca (finish /
idle push, cross-device dismissal, missed-notification replay), Grok automations (per-feature delivery).

Categories (each a `UNNotificationCategory`, threaded by task so a busy task stacks):

| Category | When | Actions | Interruption level |
| --- | --- | --- | --- |
| Needs approval | A permission request | Allow, Reject (Allow always only in-app, behind Face ID) | Time-sensitive |
| Question | The agent asked something | Reply (text input), Open | Time-sensitive |
| Done | A turn that ran longer than the threshold finished | Open, Review changes | Active |
| Failed | A turn or agent failed | Open | Active |
| Limit | A limit was hit / reset | Resume at Reset / Open | Passive |

- Body uses facts: "Done in 4m · 7 files changed +120 −14", "Needs approval · Run `pnpm test`".
- Nothing is sent for the task you're looking at on the Mac (Native's existing rule for limit alerts),
  and answering on one device clears the notification on the others (Orca's dismissal sync).
- When the phone reconnects, missed events replay as a single summary ("While you were away: 2 done,
  1 needs you"), not a burst of stale alerts.

## 8. Live Activity and widgets

**References**: Timery and Athan (content picker previewed as lock screens), Flighty ("Extensions"
group), Headway / Timery (persistent mini bar), v0 (Live Activities toggle for a coding agent).

- **One Live Activity for the Mac, not one per task** (iOS limits the number, and the user cares about
  the fleet): Dynamic Island compact = working count + needs-you count in orange; expanded = the
  longest-running task's title, current step, elapsed time, and when something needs you, the request
  with Allow / Reject buttons (interactive Live Activity via App Intents, same request IDs as the
  notification).
- **In-app mini bar** above the bottom search when you're not on Tasks: "2 working · 1 needs you" (Timery,
  Headway mini player) - tap returns to the task that needs you.
- Widgets (later): Needs-you count + latest done task; a Lock Screen accessory with the working count.
- Settings ▸ Extensions: Live Activity on/off, what it shows, widgets how-to (Grok's widget card).

## 9. Settings

Modal sheet, account-less, grouped (Claude, ChatGPT, Grok):

- **Macs**: each paired Mac (name, model, "This Mac is connected via Tailscale", last seen), rename,
  transport preference, Forget. The Mac's own Settings ▸ Devices lists paired phones with last seen and
  Revoke (Teleprompter's device list; docs/companion.md "revocable from Settings"), plus "Revoke all".
- **Notifications**: per category toggles with consequences, the "long work" threshold, quiet hours
  (Claude's Time & focus).
- **Approvals**: Require Face ID for Allow always / full-access sessions.
- **Extensions**: Live Activity, widgets.
- **Appearance**: System / Light / Dark tiles, text size with a live transcript preview (Grok).
- **Help**: connection log and troubleshoot (Orca), version of the app and of each Mac's Native, a
  version-mismatch explanation when the gateway protocol differs (Orca blocks incompatible hosts; we
  should say which side to update).

## 10. States to design up front

| State | What the user sees |
| --- | --- |
| Mac asleep | "MacBook Pro is asleep" + last-synced time; tasks shown read-only, actions disabled with the reason |
| Native closed on the Mac | Same, with "Open Native on your Mac" |
| Unreachable on this network | "Not on the same network" + switch to Tailscale / Relay |
| Revoked | "This iPhone was removed from MacBook Pro" + Pair again |
| Version mismatch | "Update Native on your Mac (or this app) to keep going" naming the versions |
| Stale data | Small "Updated 3m ago" in the Mac capsule; never silently old |
| Approval failed to send | The card stays, says "Not sent - Mac unreachable", offers Retry; never pretends |
| Interrupted turn | Shown ended with the reason (Orca), with Continue |

## 11. What the gateway must expose (`_native/*` or `_meta`)

Mapped from the screens above, beyond plain ACP: task list with status, title, agent, project, branch,
pin order and unread; the live step text and start time; turn summaries (duration, files changed, +/−);
pending permission requests and questions with stable IDs; plan entries; subagent list with live lines;
usage windows with exact reset times; notification events with dismissal sync and replay-since; Mac
identity (name, model, Native version, protocol version); pairing and revocation.

## 12. Deliberately out of scope for v1

Terminal mirror and raw keystrokes (Orca's core, but Native is ACP-first), file browsing and editing,
PR creation and git staging (Orca has them; ship later via the Mac's existing GitHub feature), and a
cloud-only mode (the Mac stays the host).
