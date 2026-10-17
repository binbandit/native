# Design research

Research done on 2026-10-17 with the Appllama MCP (a library of top-grossing iOS apps' screens) plus
read-only web sources for Orca, to inform Native's Mac app and its planned iPhone companion.

**Images never leave this folder.** Downloaded screens, contact sheets and GIF frames live under
`research/**/img/` and `research/**/sheets/` and are gitignored: they are third-party. Only these notes
are committed. "Listed" means every screen's metadata (name, flow, elements) was read; "viewed" means
the image was examined in a contact sheet. Screen ids are durable; re-fetch pixels with `get_screen(screen_ref="<app_id>/<screen_id>")`
(media links expire after about an hour).

## Scope

1. AI assistant apps: composer, streaming and thinking, agentic steps and approvals, conversation
   lists, empty states, settings, usage and limits, notifications.
2. Developer and work apps: task lists and status, triage, connecting to machines, a coding agent on
   a phone.
3. The companion: pairing with a computer, live progress, notification priming and actions.

## Documents

| File | What it is |
| --- | --- |
| `patterns.md` | The cross-app design language as concrete rules |
| `native-recommendations.md` | Prioritized changes for Native's Mac surfaces, mapped to code |
| `companion-app.md` | Screen-by-screen proposal for the iPhone companion |
| `ai-assistants/{claude,chatgpt,grok,perplexity}/screens.md` | Per-app screen ids, flows, notes |
| `dev-work/{v0,todoist,spark,termius}/screens.md` | Per-app screen ids, flows, notes |
| `companion/orca/screens.md` | Orca Mobile (not in Appllama): screen map, behavior, reviews |
| `companion/references.md` | Pairing, Live Activity and notification reference screens across apps |

## Apps studied and why

| App | Appllama id | Depth | Why |
| --- | --- | --- | --- |
| Claude | 6473753684 | All 45 listed, 30 viewed | Closest consumer analogue to a Claude Code harness; best model/effort picker; restrained palette |
| ChatGPT | 6448311069 | All 37 listed, 10 viewed | The category's default grammar; ships a "connect your desktop app" Codex screen |
| Grok | 6670324846 | All 76 listed, 20 viewed | Most agentic: build log, subagent sheet, question forms, automations, the clearest Usage page |
| Perplexity | 1668000334 | All 27 listed, 10 viewed | "N steps completed", live field while answering, quota at point of use, mode-filtered history |
| v0 (Vercel) | 6745097949 | All 58 listed, 15 viewed | The only coding agent on a phone: one-line tool rows, checkpoints, question sheet, Live Activities |
| Todoist | 572688855 | Task Management flow (7) | Calm task rows, detail sheet, action menu |
| Spark Mail | 997102246 | Inbox flow (4) | Triage grammar: buckets, unread dots, bundles, long-press actions |
| Termius | 549039908 | Host Management flow (6) | Connecting to machines; LAN discovery; "set up for AI code assistants" |
| Orca Mobile | not in Appllama | App Store listing, docs, README, repo routes, showcase GIF | User-named primary inspiration for the companion |
| Pairing / Live Activity / notification refs | see `companion/references.md` | 18 single screens across 15 apps | Companion-specific patterns |

Not in the library: GitHub, Linear, Slack, Things (searched; the library is consumer top-grossing).

## Credits

| Step | Calls |
| --- | --- |
| Boards check (none curated) | 1 |
| App searches (AI, Claude, Orca x3, dev tools, task apps, team chat) | 8 |
| Claude walk (5 pages) | 5 |
| ChatGPT walk (4 pages) | 4 |
| Grok walk (8 pages) | 8 |
| Perplexity walk (3 pages) | 3 |
| v0 walk (6 pages) | 6 |
| Todoist, Spark, Termius flows | 3 |
| Companion screen searches (pairing, approvals, live activity, computers, approve/reject) | 5 |
| Flows taxonomy, Duet flow | 2 |
| UI element catalog + two element pages | 3 |
| **Total** | **48 of the 220 (+60) budget** |

`get_credits` (free) confirmed 48 used, 1,452 remaining for October.
