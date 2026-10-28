# Tasks without a project

One direction extending Compose, Quick Entry, Home and All in view. Dark and light app captures are paired with the mock for each state.

| State | Dark app | Dark mock | Light app | Light mock |
| --- | --- | --- | --- | --- |
| n1: Compose | [App](app-n1-dark.png) | [Mock](mock-n1-dark.png) | [App](app-n1-light.png) | [Mock](mock-n1-light.png) |
| n2: Home | [App](app-n2-dark.png) | [Mock](mock-n2-dark.png) | [App](app-n2-light.png) | [Mock](mock-n2-light.png) |
| n3: Quick Entry | [App](app-n3-dark.png) | [Mock](mock-n3-dark.png) | [App](app-n3-light.png) | [Mock](mock-n3-light.png) |
| n4: Task and sidebar | [App](app-n4-dark.png) | [Mock](mock-n4-dark.png) | [App](app-n4-light.png) | [Mock](mock-n4-light.png) |
| n5: Move review | [App](app-n5-dark.png) | [Mock](mock-n5-dark.png) | [App](app-n5-light.png) | [Mock](mock-n5-light.png) |
| n6: Moving | [App](app-n6-dark.png) | [Mock](mock-n6-dark.png) | [App](app-n6-light.png) | [Mock](mock-n6-light.png) |
| n7: Moved | [App](app-n7-dark.png) | [Mock](mock-n7-dark.png) | [App](app-n7-light.png) | [Mock](mock-n7-light.png) |
| n8: Move failed | [App](app-n8-dark.png) | [Mock](mock-n8-dark.png) | [App](app-n8-light.png) | [Mock](mock-n8-light.png) |
| n9: Delete with Undo | [App](app-n9-dark.png) | [Mock](mock-n9-dark.png) | [App](app-n9-light.png) | [Mock](mock-n9-light.png) |
| n10: Managed | [App](app-n10-dark.png) | [Mock](mock-n10-dark.png) | [App](app-n10-light.png) | [Mock](mock-n10-light.png) |
| n11: Empty task | [App](app-n11-dark.png) | [Mock](mock-n11-dark.png) | [App](app-n11-light.png) | [Mock](mock-n11-light.png) |

[Build spec](no-project-spec.md). Download compare.html with these images for the full side-by-side page.

Reviewed against the mock in both appearances. The app uses the current shared composer, empty state, native sheet and Undo toast. Workflows navigation, inactive window chrome and Home after deletion follow current main.

Real Claude Code verification used Haiku 5.5 at Low effort: start from Home with no folder, write a private checklist, move to atlas with a byte-identical copy, retain the draft, and answer a follow-up from the same conversation. An empty task moved without copying; its name, settings and files survive reopening. Delete and Cmd-Z restored the private task in both appearances.

The model suite passed 11 tests on three consecutive runs; the scratch-store suite passed 8 tests. Search UI verification remains blocked by the shared battery pause before any tasks were indexed. iPad verification reaches existing host and Terminal platform errors. Final design approval remains pending.
