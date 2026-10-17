# ChatGPT (iOS)

App id `6448311069`. $299M/mo, 25M downloads, 4.83 stars, #2 Productivity. 37 screens, walked in full on
2026-10-17 (onboarding auth screens skimmed from metadata only; everything else downloaded and viewed).
Re-fetch with `get_screen(screen_ref="6448311069/<id>")`.

Why it matters for Native: the category's default grammar (most users' mental model of "an AI app"), and it
ships a **"Set up Codex mobile: connect your desktop app"** screen, which is the exact job of Native's
companion.

## Screens

| # | Screen id | Name | Flow | What's notable |
| --- | --- | --- | --- | --- |
| 00 | spl_9xsne | (video) | Welcome | Logo loader into a safety list |
| 01 | spl_3kbv8 | Onboarding Welcome | Welcome | Three icon+text safety points, black CTA |
| 02 | onb_ugbej | (video) | Onboarding | Guest chat before sign-up |
| 03 | onb_li26u | Guest Chat Home | Onboarding | Lets you chat before an account exists; login pill top-left |
| 04 | onb_opo2u | Assistant Answer | Onboarding | Answer first, sign-up later |
| 05-10 | onb_b7a1a, onb_hpa5y, onb_td88f, onb_p3kv1, onb_04adt, onb_2yfy0 | Auth sheet steps | Onboarding | Auth lives in a sheet over the chat; one field per step |
| 11 | onb_t7upr | Notifications Prompt | Onboarding | Pre-permission screen: bell icon, why, then the system alert |
| 12 | onb_gjm6m | Use Case Survey | Onboarding | Radio list, one question |
| 13 | onb_pi107 | Chat Home | Onboarding | Starter actions are plain icon rows (not cards) sitting right above the composer; "Upgrade" pill is the only colored thing |
| 14 | onb_snlen | Welcome Examples Chat | Onboarding | Example prompts as tappable reply-arrow links inside the first assistant message |
| 15 | onb_6mfgh | Task Plan Answer | Onboarding | **While generating, the primary button becomes a stop square**; scroll-to-bottom arrow floats above composer |
| 16 | onb_9arz2 | Scrolled Task Answer | Onboarding | Answer ends with numbered "reply with" asks |
| 17-18 | pay_29j3s / pay_hxuri | Plus / Go upgrade | Paywall | Segmented plan picker, Free vs plan compare table (checks vs dashes) |
| 20 | oth_swzdv | Chat Thread Scrolled | Chat | Message actions row: copy, read aloud, feedback, share, more |
| 21 | oth_sl4vk | Chat Response | Chat | Markdown with bold lead-ins |
| 22 | oth_vthob | Attach Source Menu | Chat | `+` opens an anchored popover (Camera, Photos, Files, Plugins), not a sheet |
| 23 | oth_f5gzb | Message Actions Menu | Chat | Header `...`: chat title as menu header, Share, Pin, Add members, Add to project >, Uploaded files, Archive, Delete (red) |
| 24 | oth_i9lfd | Navigation Drawer | Navigation | Wordmark + search + avatar; Projects, Images, Codex, Library, Apps; "Recents" list; floating dark "Chat" pill |
| 25 | oth_jjpqz | Projects Empty | Projects | Icon, title, one line, black small pill; search pinned bottom |
| 26 | oth_qf5yp | New Project Modal | Projects | Name + category chips, disabled CTA until named |
| 27 | oth_r84qv | Images Home | Navigation | Horizontal card rail of prompt ideas |
| 28 | oth_9bdxg | **Codex Setup** | Navigation | App tile, "Set up Codex mobile", one sentence about connecting the desktop app to continue tasks anywhere, one black Connect button; bottom: search + Chat pill |
| 29 | oth_n8qod | Library Empty | Navigation | Segmented tabs over an empty state |
| 30-34 | oth_ll4sb, oth_3x8wa, oth_3k69g, oth_m319j, oth_a34ty | Apps / GPTs | Apps | App-store-like detail pages, "Connect" pills, info tables |
| 35 | oth_cwa6p | Settings Account | Settings | Half-sheet; avatar with edit badge; groups: Customize, Account (values right-aligned: email, "Free"), Upgrade row in accent |
| 36 | oth_7mglz | Settings App | Settings | Theme (Appearance, **Accent color**), App settings (General, Notifications, Voice, Safety, Data controls, ...), Get help |

## Takeaways

- **The primary button is a state machine**: voice (empty) -> send (text) -> stop (generating). One place, one
  shape, three meanings. Users never hunt for "stop".
- **The composer is one row** on the phone (`+`, field, mic, primary). Model choice is not in the composer.
- **Menus are popovers anchored to their trigger** (attach, chat overflow); sheets are for multi-step or
  settings. Destructive items sit last, in red.
- **Starter actions are rows, not a card grid.** Three verbs with icons, close to the composer.
- **Value-in-row settings** (Subscription: Free, Appearance: System, Accent color: Default) so the list doubles
  as a status page.
- **Desktop handoff is a first-class destination**: Codex sits in the main drawer, and its empty state is a
  single "connect your desktop" action.
- Purple accent appears only on Upgrade surfaces; everything else is black/white/grey.
