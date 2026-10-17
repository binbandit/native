# Orca Mobile (Stably AI) - companion for the Orca desktop ADE

**Not in the Appllama library** (searched "Orca", "Orca Stably AI coding agent companion", and "control
coding agents from your phone": no match, 2026-10-17). Everything below comes from public, read-only
sources, paraphrased:

- App Store listing "Orca IDE" (id 6766130217, subtitle "Manage Coding Agents Remotely"): description,
  version notes, rating 4.6 from 39 ratings, review themes. Screenshots on the listing did not render.
- Orca's mobile docs (onorca.dev/docs/mobile) and README (github.com/stablyai/orca, MIT).
- The README's showcase image and GIF of the phone app (`docs/assets/feature-wall/mobile-companion-app-showcase.*`,
  saved under `img/`, gitignored), and the mobile app's route list (`mobile/app/*`) for the screen map.

Why it matters: it is the closest product to what Native's companion should be (a phone remote for a
desktop that runs many coding agents in worktrees), it is well reviewed, and the user named it the key
inspiration.

## Screen map (from the app's routes and the showcase)

| Area | Screens | What's there |
| --- | --- | --- |
| First run | onboarding, pair, pair-scan, pair-confirm, notification-opt-in | Scan a QR from the desktop, or paste a pairing code; numbered steps; a confirm step ("pair with this desktop?") naming the machine; then notification opt-in |
| Home | index | "Welcome back"; three stat tiles (agents spawned, agent hours, PRs created); **Desktops** list with status ("Connected · 40 worktrees · 5 active" / "Disconnected"); **Resume** (last worktree); **Tasks** (GitHub · Linear); **Quick actions** (Pair desktop, New workspace); **Account usage** per provider account with 5h and 7d bars |
| Host | h/[host]/index | All worktrees across hosts in one list: filter, Recent, Repo; **Pinned** and **Active** sections; row = status dot (working / done / waiting), branch name, PR number badge, repo + branch subline, last agent line as a one-line preview |
| Session | h/[host]/session/[worktree] | Tabs per worktree (agent, shell, PLAN.md, +); terminal mirror *or* native chat view (per-device default, per-tab override); accessory key row (mic, Paste, Esc, Tab, arrows, Ctrl-C); composer "Type a command..." with mic and send |
| Work | tasks, pr, review, source-control, files, history, agent-history | GitHub/Linear tasks to start worktrees from, PR view, review, stage/commit, file tree with media playback, session history and resume |
| Account | accounts | Switch provider accounts, usage and reset timers, spend reset credits |
| Settings | settings, terminal-, voice-, native-chat-, browser-settings, notifications, troubleshoot, connection-log, about | Text size 50-200%, autocorrect off by default, dictation, a **connection log** and a troubleshoot page |

## How it behaves (docs + version notes)

- **Thin client.** Nothing runs on the phone; the desktop is the source of truth and the phone
  disappears when the desktop is asleep or closed, with a clear message instead of an endless
  "connecting".
- **Pairing**: single-use code that expires in minutes; QR or paste; one token per phone; the phone
  labels the host with its machine name and OS; renaming on the desktop propagates. Revoking on the
  desktop makes the phone show an auth error with Retry / Re-pair / Remove.
- **Transport**: LAN direct, Tailscale-aware reconnect, or Orca Relay (needs sign-in). The phone races
  direct vs relay and upgrades to direct when it can. Versioned protocol blocks incompatible hosts.
- **Notifications**: push when an agent finishes or goes idle, mirroring desktop notifications;
  notifications dismissed on one device are dismissed on the other; missed ones replay on reconnect.
- **Replies**: quick answers or free text to a waiting agent, `@` file mentions, agent `/` commands,
  image attachments, a model/options pill row, permission prompts and questions handled inline.
- **Starting work** on the phone opens a tab on the desktop without stealing its focus.
- Recent fixes worth copying: failed sends are marked "Not sent" and the text returns to the draft;
  a reply interrupted by a desktop crash is shown as finished with an explanation; plans render as
  plans; approval requests show what the agent actually asked for; the workspace list follows the
  desktop's pinned order.

## Review themes

- Praised: fastest way to manage agents remotely, reliable auto-reconnect, quick setup, voice input,
  multi-tab handling, smoother than terminal-only remotes.
- Complaints: no way to close a terminal on iPad; reasoning disclosure that won't collapse, raw JSON
  shown for reasoning, answer and reasoning rendered above the user's message (ordering bug).

## Takeaways for Native

1. Home is a **dashboard of machines and attention**, not a chat list: desktops with live counts,
   resume-last, quick actions, usage per account.
2. One flat list of work across machines with **Pinned / Active** sections and a status dot per row.
3. A session screen that defaults to a readable transcript but keeps raw terminal one tap away.
4. Pairing is QR first, code second, and **always shows a confirm step naming the Mac**.
5. Make the connection observable: a connection log and a troubleshoot page beat a spinner.
6. Notification state syncs across devices; nothing is lost while the phone is offline.
7. Copy their recent fixes as requirements (unsent drafts restored, interrupted turns explained, the
   transcript order never inverted, reasoning collapsible and never raw).
