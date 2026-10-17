# Companion references (cross-app)

Screens pulled on 2026-10-17 for the companion's pairing, live-activity and notification questions.
Images are under `pairing/img`, `live-activities/img`, `notifications/img` (gitignored). Re-fetch any
with `get_screen(screen_ref="<app_id>/<screen_id>")`.

## Pairing and connecting to a computer

| App (id) | Screen | What's notable |
| --- | --- | --- |
| Alfred Camera (966460837) | oth_9l7v2 QR Code Pairing | Big title, one line ("scan with the other device or sign in with the same account"), large QR, **expiry countdown** ("expires in 29 min 59 sec") with the numbers in the accent; Help top-right |
| OurPact (954029412) | oth_s43wr Quick Pair | Numbered steps; QR, then a **six-letter fallback code** set wide; "detailed instructions" link |
| Authenticator (1602061522) | onb_gr25t QR Scanner | Title with a QR glyph, camera viewfinder in a rounded card, import-from-photos button, Skip |
| Ledger Wallet (1361671700) | oth_cgu7t Choose Sync Method | Sheet of methods, each icon + title + one line on when to pick it ("if you already have it synced on another phone or computer") |
| Duet Display (935754064) | oth_ogx9x Wired / oth_4orbp Air | "Connect to your Mac or PC" with device art; empty discovery explains **what to turn on on the computer**; "How to get set up?" link; Wired / Air as tabs |
| Teleprompter.com (1420515755) | oth_n52fi Use as Remote, oth_ih2fb Control This Device | Two transports as rows with a bold tradeoff under each ("More stable - needs internet" / "No internet needed - close range, pair each time") |
| Teleprompter.com (1420515755) | oth_dgrba Device Management | "My devices": icon, name with a green "(current)" tag, last active time, Sign out per row; "Sign out of all devices" |
| Termius (549039908) | oth_lm7dw Discover Devices | Radar pulse + "Searching devices in local network..." |
| ChatGPT (6448311069) | oth_9bdxg Codex Setup | "Set up Codex mobile: connect your desktop app to continue tasks from anywhere" + one Connect button |

## Live Activities and persistent progress

| App (id) | Screen | What's notable |
| --- | --- | --- |
| Timery (1425368544) | oth_nmg15 Live Activities | Auto-show toggle; Lock Screen & StandBy content toggles; appearance; a note that Liquid Glass / Reduce Transparency may override; **mini "running" bar** above the tab bar |
| Flighty (1358823008) | oth_63t2p Settings | An "Extensions" group: Live Activities, Lock Screen widgets, Home Screen widgets, Apple Watch |
| Pacer (600446812) | oth_a8cfl Onboarding Live Activity | Education sheet: illustration of the lock screen, one-line benefit, Continue |
| Athan Pro (743843090) | oth_o4o9k Live Activity Settings | Toggle + two style previews rendered as lock screens, radio pick |
| Headway (1457185832) | oth_rm7jh Search Landing | Persistent mini player docked above the tab bar with a thin progress line |
| v0 (6745097949) | oth_tmv9r Settings | Notifications and **Live Activities** toggles for a coding agent |

## Notification permission priming

| App (id) | Screen | What's notable |
| --- | --- | --- |
| ChatGPT (6448311069) | onb_t7upr | Bell, "let it tell you when tasks are done", one line, then the system alert |
| Windy (997079492) | onb_3cyol | A **real example notification** on a lock-screen mockup; Maybe later / Allow |
| Open (1482725254) | onb_nxlpb | Lock-screen mockup with a sample, single CTA, "Later" top-right |
| FamilyWall (496889629) | onb_y2irb | Illustration, "you can always change this later", Enable / Skip |
| Pep AI (6758682710) | onb_8w7f8 | Confirmation state: "Notifications enabled" pill with a check |
| Grok (6670324846) | oth_a46zr New Automation | Inline "Enable notifications" banner where a feature needs them |

## Searched without a useful match

- "approve or deny sign-in request" and "review request with Reject/Approve" (semantic): the library has
  no approval-card reference worth copying. Approval design is derived from Claude, Grok and v0 instead.
