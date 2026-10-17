# Grok AI (iOS)

App id `6670324846`. $29M/mo, 3M downloads, 4.87 stars, #7 Productivity. 76 screens, metadata walked in
full on 2026-10-17; 20 stills viewed (agent build, usage, questions, search activity, drawer, settings,
automations, skills, menus) and 20 more downloaded for reference. Skipped imagery: Imagine, Image
Editor, Video Generation, Country Explorer/Metrics (generated mini-apps), web views.
Re-fetch with `get_screen(screen_ref="6670324846/<id>")`.

Why it matters for Native: the most **agentic** consumer AI app in the library. It shows a long-running
build agent on a phone (narrated log, collapsed thoughts, subagent sheet, elapsed time), structured
questions from the agent, automations with completion notifications, and the clearest usage/limit page.

## Screens

| # | Screen id | Name | Flow | What's notable |
| --- | --- | --- | --- | --- |
| 00-01 | spl_lmviq / spl_a94qg | Welcome / Sign in | Welcome | Photo backdrop, mono tagline, SSO buttons |
| 02-03 | onb_k7etx / onb_dekek | Onboarding / Terms update | Onboarding | Terms change as its own interstitial with sign-out escape |
| 04 | onb_upn9k | Ask Home | Onboarding | Mode tabs on top, suggestion chips, composer with `+`, "Auto" pill, mic, black "Speak" pill |
| 05-07 | pay_mqb6h, pay_yb1xf, pay_3lbtc | Paywalls | Paywall | Tier segmented control, "Skip" pill instead of a tiny X |
| 08 | oth_bv6z1 | Chat Home | Chat Setup | Empty state = faint mark + chips; composer mode pill "Fast" |
| 09 | oth_c9q8e | Add Menu | Tools | `+` popover: Camera, Photo/Video, Files, divider, Connectors, Skills |
| 10 | oth_sg1z1 | Model Selection | Chat Setup | Mode popover from the pill: upsell header, rows with icon, name, one-line purpose + model version, selected row filled grey with check |
| 11 | oth_h2qe4 | Add Connector | Tools | Logo tile rows with "Connect" pills |
| 12 | oth_sft8h | Skills Library | Tools | "My skills" empty card with "Create with Grok"; built-in skills as icon + title + description rows |
| 13 | oth_w0dzz | Prompt Composer | Skills | Skill mention chip inside the text field |
| 14-17 | oth_216ll, oth_0c29v, oth_phokh | Skill setup questions | Skills | **Question card docked above the composer**: question, pager `< 1/3 >`, lettered options (A-E) each with title + description, "type your own" field, Skip / Next pills |
| 16 | oth_til03 | Navigation Drawer | Others | Profile row, history, bottom search + new chat |
| 18-19 | oth_enlp8 / oth_m5tpx | Skill Created / Schedule summary | Skills | Completion message with named result, suggested next prompts |
| 20-24 | oth_m5heu ... oth_362wd | Voice, Imagine, Video, Editor | Media | Not studied (out of scope) |
| 25 | oth_ihuwh | New Chat | App Building | "Build with Grok" placeholder |
| 26 | oth_jnqo1 | Agent Build Chat | App Building | **Log = short first-person narration paragraphs separated by collapsed "Thoughts >" rows.** No tool cards |
| 27 | oth_nmges | Agent Running Sheet | App Building | Bottom sheet "1 agent running": subagent row = icon, task title, live status ("Reading file") |
| 28 | oth_enr3w | Build Progress Chat | App Building | "1 agent used" chip at the end of a turn opens that sheet; share bar pinned at top |
| 29 | oth_360nw | Build Result | App Building | **Inline limit card in the transcript**: clock icon, "you've hit your limit", one line, black "add more usage" CTA; result card (preview, title, "Not published", share, play); action row ends with elapsed seconds |
| 30-37 | oth_jl41l ... oth_509zz | Country Explorer | Generated app | Out of scope |
| 38 | oth_xvh6g | Chat File Actions | Others | File card popover; thoughts rows |
| 39 | oth_enfd0 | Navigation Drawer | Navigation | Account switcher, blue upgrade card, Automations / Projects / Bot, "Conversations" with 2-line titles + time, selected = grey fill; bottom: gear, search pill, compose circle |
| 40 | oth_6pvml | Automations Empty | Automations | Icon, title, one line ("run any prompt on a schedule, get reminded when it completes"), "New automation" pill |
| 41 | oth_a46zr | New Automation | Automations | Name, dashed "Add trigger", instructions with mode chip, Push/Email toggles, inline "Enable notifications" banner when OS permission is off |
| 42-43 | oth_gn5h7 / oth_5515k | Projects empty / New | Projects | Same empty-state recipe |
| 44 | oth_k68zk | Voice Settings | Settings | Chips, segments, slider |
| 45 | oth_26t19 | Account Switcher | Navigation | Popover with check, add account, red sign out |
| 46 | oth_lm0io | Settings Overview | Settings | X close; account card; SuperGrok + **Usage** rows first; App / Grok groups; floating "Search settings" pill |
| 47-48 | oth_nbusx / oth_zm8vw | Grok & Voice / Data & Legal | Settings | Groups with labels, red sign out |
| 49 | oth_88qjq | **Usage** | Settings | "Weekly limit": big "1% used", "Resets <day, date, time>" right-aligned, thin bar, breakdown rows with colored dots ("Voice 1% of total"), footnote on reset and order of spend; Extra credits: Balance, Buy more, Auto top-up |
| 50 | oth_md8dd | Appearance | Settings | System/Day/Night tiles, code-wrap toggle, text-size slider with live chat preview |
| 51 | oth_gfrbh | Haptics | Settings | Toggles with helper |
| 52 | oth_sql7x | Notifications | Settings | One toggle: notify when a long-running answer finishes |
| 53 | oth_ttje4 | Widget Setup | Settings | Illustrated how-to card with dots |
| 54-61 | oth_j65kq ... oth_94hcl | Imagine, Customize, Memory, Advanced, Kids, Dictation, Data, Storage | Settings | Advanced: one helper paragraph explains all toggles in the group; "Paste as file: Always ask" select |
| 62-63 | oth_styfp / oth_0mxp3 | Web pages | Web | In-app browser with domain pill |
| 64 | oth_gv1l8 | Chat Search Activity | Chat | **Live step header with a dot-grid spinner + elapsed seconds**; finished sub-steps listed with result counts and source chips; primary button = stop |
| 65 | oth_hc2nw | Chat Response | Chat | "Thoughts >" above answer; bold lead sentence |
| 66-67 | oth_milmy / oth_jn1rg | Response + actions | Chat | Regeneration pager `< 4/4 >`; action row with elapsed time right-aligned; suggested follow-ups as reply-arrow rows |

## Takeaways

- **Narrate, don't dump.** Long agent runs read as short status paragraphs written by the agent, with the
  raw reasoning folded behind one quiet "Thoughts >" row each time. Works on a phone; would declutter a
  desktop transcript too.
- **Live work has a clock.** The active step shows a spinner and a ticking seconds count; finished
  turns show total elapsed time in the action row.
- **Subagents are a count chip + a sheet**, not inline noise: "1 agent used" opens a list of agents with
  their current activity.
- **Agent questions get a real form**: pager, lettered options with descriptions, free-text fallback,
  Skip/Next. Letters double as keyboard accelerators on desktop.
- **Limits are inline and calm**: when a run hits a limit, the transcript gets a card with what happened
  and one action; the Usage page shows percent used, exact reset time, and what consumed it.
- **Notifications are tied to long work**: the only notification setting is "tell me when a long-running
  task finishes"; automations each choose Push and/or Email.
- **Primary button state machine** again: Speak (empty) -> send arrow (text) -> stop (working).
