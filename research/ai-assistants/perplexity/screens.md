# Perplexity (iOS)

App id `1668000334`. $7M/mo, 700K downloads, 4.82 stars. 27 screens, metadata walked in full on
2026-10-17; 10 stills viewed (answer, follow-ups, options, models, Computer, home, library, connectors,
settings), the rest from metadata. Re-fetch with `get_screen(screen_ref="1668000334/<id>")`.

Why it matters for Native: cleanest "steps completed" summary, inline citations as chips, the best example
of **quota microcopy at the point of use**, and "Computer" - a background multi-step agent mode with its
own history filter.

## Screens

| # | Screen id | Name | Flow | What's notable |
| --- | --- | --- | --- | --- |
| 00-02 | spl_o8pez, spl_du1aj, spl_arwgc | Welcome / Home / Create account | Welcome | Guest home first; segmented Search/Computer switch on top |
| 03-05 | onb_b5tzr, onb_g3ur6, onb_twzwy | Sign-in steps | Onboarding | Email magic link sheet |
| 06 | onb_q6zcc | Home | Onboarding | Dismissible announcement card docked above the composer; composer: `+`, "Model" chip, incognito, mic, accent voice circle |
| 07-08 | pay_8k11y / pay_65taz | Pro / Max offer | Paywall | Model logo strip as the value prop |
| 09 | oth_drnqr | Home Search | Search | Wordmark only; everything else is the composer |
| 10 | oth_t1yt6 | Answer Results | Search | **"2 steps completed >"** one-line summary above the answer; inline mono source chips ("datacamp +3"); while streaming the field reads "Ask a follow up..." with a stop square inside it and a separate new-thread button |
| 11 | oth_p8bd9 | Follow-up Thread | Search | Footer: share, rewrite, copy, "20 sources" with stacked favicons, more; follow-up suggestions as reply-arrow rows with hairlines |
| 12 | oth_292w5 | Options Sheet | Search | 4 tiles (Image, Camera, File, Connectors); **"1 upload remaining today"** under the tiles; modes as rows with check / lock |
| 13 | oth_0v7ef | Models Sheet | Search | "Best" pinned first in a filled row; provider logos; "max" badges |
| 14 | oth_eriyu | Computer Mode Empty | Search | Device icon, title, one line ("runs multi-step workflows in the background from a single prompt"), upgrade pill; composer placeholder "Do anything..." |
| 15 | oth_uy3up | Discover Feed | Others | Out of scope |
| 16 | oth_onhee | Library | Library | Account header with settings gear; Spaces / Artifacts / Connectors; **History filter chips by mode** (All, Computer, Deep research, ...); row = title + mono relative time; teal "New +" pill; bottom search |
| 17-19 | oth_wgx6f, oth_93xqz, oth_tnxe5 | Spaces | Spaces | Illustrated card, form with privacy radios |
| 20-21 | oth_igbhj / oth_5zo6b | Artifacts | Artifacts | Segmented chips, type filter popover |
| 21 | oth_zcw8n | Connectors | Connectors | One-line explanation of why to connect; chips Popular / All / **Connected**; rows logo + name + one line |
| 22 | oth_3swfx | Connector Detail | Connectors | Logo, overview bullets, fixed CTA |
| 23 | oth_ohnli | Settings Account | Settings | Avatar + "Manage account"; big Pro card; Incognito toggle; Usage and credits; Orders; Theme & App Icon |
| 24 | oth_cjfcc | Settings Preferences | Settings | Value-in-row ("Map provider: Apple Maps"); an unseen-feature dot on "Tasks" |
| 25 | oth_xkyfl | Settings Support | Settings | Red log out, version footer |

## Takeaways

- **Count the work**: "N steps completed" is a better collapsed header than "Thinking..." because it is a
  fact and it changes as work happens.
- **You can type while it answers.** The field stays live during streaming; stop lives inside the field.
- **Limits at the moment they matter**: remaining uploads printed under the upload tiles, locked modes show
  a lock, not an error later.
- **History is filterable by mode** (a "Computer"/background agent run is a different kind of thing from a
  quick answer), with a single "New" pill.
- **Brand color is one teal**: voice button, new pill, selected checks. Everything else is warm neutral.
