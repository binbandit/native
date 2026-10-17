# Termius (iOS)

App id `549039908`. $200K/mo, 4.7 stars, #11 Developer Tools. 36 screens; studied the **Host Management**
flow (6 screens) on 2026-10-17. Re-fetch with `get_screen(screen_ref="549039908/<id>")`.

Why: a phone app whose whole job is "connect to a machine", and it now offers to set hosts up for AI code
assistants.

| Screen id | Name | What's notable |
| --- | --- | --- |
| oth_2yu0u | Hosts Empty | Icon tile, "Create host" + one line; the empty state *is* the form (address field + Continue); "Discover local devices" link below |
| oth_lm7dw | Discover Devices | Sheet with a pulsing radar glyph and one status line ("Searching devices in local network...") - LAN discovery as a calm waiting state |
| oth_c4gyd | Hosts Add Menu | `+` popover: New host, New group, Import hosts |
| oth_dgiex | Edit Host Basics | Grouped form; an "AI Agent" card: set this host up for AI code assistants (Claude Code, Gemini, OpenCode) |
| oth_18ct8 | Edit Host Advanced | Credentials, variables, terminal theme previews |
| oth_zuur0 | New Host Group | Parent group picker, protocol toggles |

Takeaways
- The empty state can be the first step of the task, not a picture plus a button.
- Local discovery deserves its own waiting screen with one honest status line.
- Floating three-tab bar (Vaults, Connections, Profile) - the app is small, the tabs are few.
