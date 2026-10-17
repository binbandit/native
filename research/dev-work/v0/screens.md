# v0 by Vercel (iOS)

App id `6745097949`. $50K/mo, 4.84 stars, #57 Developer Tools. 58 screens, metadata walked in full on
2026-10-17; 15 stills viewed (build transcript, checkpoints, questions, tasks, preview menu, summary,
history, GitHub connect, usage, settings); auth, pricing and the generated apps from metadata only.
Re-fetch with `get_screen(screen_ref="6745097949/<id>")`.

Why it matters for Native: the library's only real **coding agent on a phone**. Its transcript is the same
shape as Factory/Conductor's tool rows, proving that grammar survives on a 6-inch screen, and it adds
checkpoints, a question sheet, a task list and Live Activities.

## Screens

| # | Screen id | Name | Flow | What's notable |
| --- | --- | --- | --- | --- |
| 00-07 | spl_oz8tq ... onb_5z9x8 | Welcome, sign-in, OTP, terms | Onboarding | Web auth in an in-app browser, OTP cells, success page "close this tab" |
| 08 | onb_62hq0 | Home | Onboarding | Menu, mark, play (preview) button; composer: `+`, "Ask v0 to build...", mic |
| 09-14 | pay_5g9md ... pay_42ozz | Pricing / model pricing | Paywall | Web pages; per-model token rates |
| 15 | oth_06nxt | Builder Loading | Calorie build | Composer stays put while the project spins up |
| 16-17 | oth_cp74v / oth_n3ge0 | Build Chat | Calorie build | **One-line tool rows** in tertiary grey with a kind icon and a past-tense human title ("Explored project structure", "Read globals.css", "Themed the app green", "Built macro bars"), chevron to expand; **"Thought for 14s"** rows; short narration paragraphs in primary text between them |
| 18 | oth_vfast | Preview Update Chat | Calorie build | **Checkpoint card**: "v1" + summary + play; directly under it "10 files changed" with a green `+796` pill and chevron; then an inline screenshot proving it rendered |
| 19 | oth_pecdr | Build Response | Calorie build | Final bulleted summary |
| 20-21 | oth_vw3zr / oth_nd9jv | Preview Launch / Overflow | Calorie build | Preview overflow: share, favorite, delete icons row; Env variables, Integrations; Duplicate, Rename; Open in browser, Restart preview, View logs, Publish |
| 22-26 | oth_i9hee ... oth_tc6mp | Generated app | Calorie build | Out of scope (the built app) |
| 27 | oth_ud9x2 | Builder Clarification | Pet build | **Questions card in the transcript**: icon, "Questions", "4 questions to answer", one button to answer. Non-blocking |
| 28-30 | oth_iu6w3, oth_3bm7z, oth_05u6u, oth_nefs7 | Question sheets | Pet build | Sheet per question: big title, "Question 1 of 4", options with title + description, "Other", Skip / Next |
| 31 | oth_tqbtj | Tasks Question | Pet build | **Plan as a checklist**: large "Tasks" title, round checkboxes, the active item has a dashed (spinning) ring |
| 32 | oth_2td8m | Answered Questions Chat | Pet build | Questions card flips to "4 of 4 answered" with a key/value summary; an automatic user message records the answer |
| 33-37 | oth_fk1rz ... oth_7n8ak | Pet Build Chat | Pet build | Long runs: "Scanned project files", "Planned build", "Wrote types", "Checked debug logs"; a second checkpoint "25 files changed +2021" |
| 38-39 | oth_splf3 / oth_zkrgx | Preview Result | Pet build | Screenshot cards as verification |
| 40 | oth_eo0oe | Build Summary | Pet build | "Finalized" row; summary with bold product name, bullets, a caveat (data is local only), and an offer for the next step |
| 41-47 | oth_zjyii ... oth_ewexo | Generated app | Pet build | Out of scope |
| 48-50 | oth_fkfcv, oth_b817k, oth_kswng | Add To Chat | Attachments | Media tiles + chat sources in one sheet, nested popover |
| 51 | oth_bls8t | GitHub Connect | GitHub | Sheet: both logos with a link glyph, title, one line, then **three icon rows explaining what will happen** (redirect, permissions, authorize), black Connect |
| 52 | oth_g2ads | Chat History | Chat mgmt | Project switcher pill in the header; dismissible coach-mark card (long-press to favorite/delete); "Drafts" rows with a preview thumbnail + title + relative time; bottom search + "New Chat" pill |
| 53-54 | oth_rzkar / oth_7815b | Account menu / Account | Settings | Sheet with avatar header, red sign out; danger zone |
| 55 | oth_31laq | Usage & Billing | Settings | Current plan "Free", Monthly credits "0.22 / 5", **Credit reset "in 30 days"**, Manage billing (external-link glyph) |
| 56 | oth_tmv9r | Settings | Settings | Notifications, **Live Activities** toggle, preview gesture, show prompts, haptics, shake to send feedback |

## Takeaways

- **Tool rows are sentences, not commands.** Past-tense, human verbs, one line, tertiary color, kind icon,
  chevron. Commands and paths live one tap deeper. This is Factory's row with friendlier titles.
- **Thinking shows its duration** ("Thought for 14s"), which is both honest and calm.
- **Checkpoints punctuate long runs**: version label + summary + preview, then a files-changed row with a
  green additions count. A natural "review this" anchor, and a natural notification payload.
- **Questions don't block the transcript**: a card says how many questions are waiting; answering happens in
  a sheet; afterwards the card becomes a compact answer summary.
- **The plan is a checklist** with a live ring on the current item.
- **Explain before redirect**: OAuth gets a sheet that lists what's about to happen.
- **Usage is three numbers**: plan, credits used / total, time to reset.
