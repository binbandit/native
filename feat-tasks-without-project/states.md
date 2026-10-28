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

Final review updates: `39e99171` requires an explicit agent close acknowledgement. Process snapshots never authorize file deletion. Cleanup runs before history deletion; a refusal keeps the task listed and its files intact. The real Claude task at `8fbcc3da` verified final folder and ownership cleanup after the Undo window. The final copy separates the reason and recovery into paragraphs.

| Additional state | Dark app | Dark mock | Light app | Light mock |
| --- | --- | --- | --- | --- |
| n12: Delete refused, task retained | [app](app-n12-dark.png) | [mock](mock-n12-dark.png) | [app](app-n12-light.png) | [mock](mock-n12-light.png) |

Native owns the system alert's material, font and corner geometry; the mock uses the approved semantic palette for its hierarchy and copy. The final alert was checked in both appearances with a scripted fixture that rejects close; its task, ownership and exact file bytes remained.

Validation: final Debug build has zero repository warnings; strict lint passed for 77 changed Swift files. Fourteen model tests cover startup, move, reopened identities, Git exclusion, Undo, cleanup ordering and refusal/retry. Thirty focused host/policy tests include unsupported close, rejected close and an escaped writer. Eight scratch-store tests and five keyboard-document tests passed. Release/Nightly compiled with archive sizes 48.1/48.2 MB against main's 49 MB budget and installed sizes 117.7/117.8 MB against 118 MB. The last edit only separates alert paragraphs; it has its own Debug build and visual check.

Verification limits: the shared iPad compile check stops in host/Terminal/platform code; search UI was paused on battery with no tasks indexed. Projectless scratch execution is local; paired hosts still require a project. An agent unable to acknowledge closure retains the task and files with the failure message. Visual approval remains pending; do not merge.

Final-head CI passed, including the iOS app build, all package tests and pullfrog approval. The standalone local iPad typecheck helper still reports shared platform errors. Final-head model tests passed (14).

Latest main integration: `a770a749` merges `48968dae`, resolves RootView by preserving Move presentation and sidebar insights, and passes Debug build, zero-warning check, lint and all 14 model tests. [Dark integration Move sheet](integration-move-dark.png) / [light](integration-move-light.png), matching mock n5, were checked in the running app. The standard composer is shown in this fixture. CI/review rerun on this merge; the preceding complete green set covered 39e99171.

Filtered-sidebar follow-up: [reproduction, fix and remaining capture checklist](filter-review.md). The fixed build passes; after captures are pending because the screen locked before UI verification. Existing state pairs above have not been replaced. Visual check pending.
