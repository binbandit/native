# Claude by Anthropic (iOS)

App id `6473753684`. $68M/mo, 8M downloads, 4.72 stars, #4 Productivity. 45 screens (3 videos), walked in
full on 2026-10-17. Re-fetch any screen with `get_screen(screen_ref="6473753684/<id>")`.

Why it matters for Native: the closest consumer analogue to a Claude Code harness (it even shows a Claude
Code tool-call preview), the best-in-class model/effort picker, and a restrained, warm-neutral visual
system that proves "almost no accent" works at scale.

## Screens

| # | Screen id | Name | Flow | What's notable |
| --- | --- | --- | --- | --- |
| 00 | spl_93nl3 | (video) | Welcome | Line-art animation, pill CTA |
| 01 | onb_2cbgy | (video) | Onboarding | Whole sign-up journey on video |
| 02 | onb_damcd | Welcome Sign In | Onboarding | Serif headline, two black SSO pills, quiet email field, legal footer |
| 03 | onb_q0wwp | Email Verification | Onboarding | Envelope card, "change email" escape hatch |
| 04 | onb_pwow6 | Terms Consent | Onboarding | Progress dots, consent checkboxes in one card, CTA pinned bottom, "verified as" footer |
| 05 | onb_na2mw | Age Experience Notice | Onboarding | System-style sheet |
| 06 | onb_7r7ri | Age Range Permission | Onboarding | iOS permission alert over dimmed step |
| 07 | onb_2go0r | Name Entry | Onboarding | One field per step, disabled CTA until valid |
| 08 | onb_akrs4 | AI Training Consent | Onboarding | Explanation card with the toggle inside it, default on, "change anytime" |
| 09-11 | pay_otlhi / pay_ksmoa / pay_gt7x3 | Free / Pro / Max plan | Paywall | Segmented Free/Pro/Max, one card per plan, monthly vs annual tiles with "save 10%", "usage limits apply" footnote |
| 12 | oth_33c3u | (video) | Voice settings | Voice carousel + mode choice |
| 13 | oth_4xxu2 | Home | Chat | Centered mark + serif time-of-day greeting; upgrade card docked on top of the composer; composer row: `+`, model pill ("Sonnet 5 Medium", effort in secondary grey), mic, black voice-mode button |
| 14 | oth_vtujo | Add to Chat | Chat | Sheet: 3 square tiles (Camera/Photos/Files), recent photos, Add to project (value + chevron), Connectors, Memory toggle |
| 15 | oth_gi3ea | Model Picker | Model | Rows = name + plan badge + one-line purpose; check on selected; footnote on availability; Effort and More models as separate groups |
| 16 | oth_9ni8q | Effort Picker | Model | Low / Medium (Recommended) / High / Extra / Max ("5x or more usage" amber badge); footnote: higher effort = slower and burns limits faster |
| 17 | oth_yvctj | More Models | Model | Legacy models behind a second level |
| 18 | oth_obfe4 | Chat Thread | Chat | User message = right grey bubble; collapsed one-line work summary with clock icon + chevron; artifact card; assistant text unbubbled, serif |
| 19-20 | oth_87nea / oth_r1t8b | Code Artifact (+menu) | Artifacts | Full-screen code, X + title + overflow (Publish / Copy / Save as file) |
| 21-22 | oth_svd3w / oth_k1q2c | Chat Response | Chat | Numbered/bulleted blocks, inline code chips, scroll-to-bottom button centered above composer, response action row (copy, share, read aloud, thumbs, retry), tiny disclaimer |
| 23-24 | oth_7chz6 / oth_b4n2p | Voice intro / session | Voice | Glow + big mic, model pill stays in the control row |
| 25 | oth_p8rxl | Model Picker Sheet | Model | Same picker at a medium detent over the chat |
| 26 | oth_0n6es | Artifact Chat | Artifacts | Work summary line reads as a sentence, not "Thinking…" |
| 27 | oth_9mz4l | Pomodoro Artifact | Artifacts | Live artifact full screen |
| 28 | oth_8ujyb | Voice Input Composer | Chat | Dictation replaces the control row: cancel X, live waveform, stop square, accent send circle |
| 29 | oth_9li2f | Navigation Drawer | Projects | Wordmark, 4 nav rows with line icons, selected = grey pill, "Recents" + "All chats >", avatar + floating dark "New chat" pill |
| 30 | oth_qc0r8 | Artifacts Empty | Artifacts | Small circled icon, one grey line + one description line |
| 31 | oth_c59zw | Claude Code Upsell | Others | Tool calls rendered as a hairline table: bold verb (Grep/Read/Edit) + mono subject; diff below with green add-tint fading out |
| 32 | oth_vz1oz | Create Project | Projects | Two questions as field labels, check-circle confirm in nav |
| 33 | oth_fl0d8 | Chats Empty | Chats | Filter popover (All / Pinned) |
| 34-35 | oth_mjp03 / oth_51l93 | Settings | Settings | Modal with X + info; account card; upgrade card; grouped sections (Account, App, Appearance); theme preview cards; Log out alone in red |
| 36 | oth_jdon3 | Profile | Settings | Save as a check-circle in the nav bar |
| 37 | oth_wt1lt | Time & Focus | Settings | Break reminders + quiet hours with weekday chips |
| 38 | oth_267dv | Privacy | Settings | Explanation card + single toggle |
| 39 | oth_7heb6 | Capabilities | Settings | Toggle rows with multi-line consequence copy; a forced-on toggle explains why ("required by ...") |
| 40-42 | oth_9zxhx / oth_exvyu | Connectors (+menu) | Settings | `+` opens Browse / Add custom |
| 41 | oth_5ca0d | Chats List | Chats | Icon + title + relative time; search field pinned at the bottom; floating "New chat" pill |
| 43 | oth_vd3d4 | Permissions | Settings | Rows show current grant on the right ("Allowed", "Read & write") |
| 44 | oth_w8y2d | Voice Settings | Settings | Carousel of voices, language/speed rows |

## Takeaways

- **Accent is nearly absent.** Brand coral appears on the logo mark and the send button only. Toggles use
  system blue; CTAs are black pills. Everything else is warm grey.
- **One composer, two rows.** Text on top; a control row of `+`, a single model+effort pill, mic, and a primary
  round button whose meaning changes with state (voice when empty, send when typed, stop while dictating).
- **Work is summarized, not narrated.** Between a prompt and its answer sits one quiet line (icon, a sentence
  describing what was done, chevron). The reasoning is one tap away, never in the way.
- **Cost is disclosed where the choice is made.** Effort levels carry "Recommended" and "5x or more usage"
  badges, and a footnote says higher effort uses limits faster.
- **Tool calls are a table, not cards.** Verb in sans bold, argument in mono, hairline separators, diff below.
- **Settings are explanatory.** Each toggle says what it does and what happens when off; dependent toggles
  say what requires them; permission rows show their current value.
- **Empty states are two lines.** Icon in a soft circle, a title, one sentence on what will appear.
