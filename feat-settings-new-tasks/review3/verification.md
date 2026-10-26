# PR 134 continuation

Revision: f872dc41 (includes merge of origin/main at this check).
Instance: cx-cont-134, isolated Debug only. No real agent session needed.

The interrupted worktree was clean at ed9c057d. All pullfrog threads were resolved, and the latest review reported no new issues. This continuation moves every load source/error under its name, preserves shared token and control columns, dims off names directly, allows collapsed summaries to shrink, counts multiple sources as "N on · N sources", applies the group's narrow layout to load summaries, and names the Modes destination in its footer link.

Source review against design comment 6397449270:

1. One budget note, additional caveats in its popover. No uncounted suffix on the headline.
2. User and Native sources are quiet; value menus share a trigger implementation.
3. Collapsed summaries are single-line and count multiple sources.
4. Load rows use one name/detail layout, token column and control slot. Off names dim.
5. Connection failures have one detail line, Review action, and an unknown count dash.
6. Modes editor is linked from the Agent footer.
7. Unmanaged source stacks omit the organization layer.
8. Managed header/scope identity, winning-layer lock, and result reason remain present.
9. Real instruction inventory and fixtures are scoped to the selected project; regression covers All projects, another project, and pier.
10. Unavailable choices explain the fallback under their label. Reset appears only where the unavailable choice is stored.
11. All settings groups use the same narrow thresholds; load summaries now participate.
12. Keyboard focus visuals require a fresh unlocked capture.

| Changed state | Matching mock | Dark capture | Light capture |
| --- | --- | --- | --- |
| All projects defaults | B1 | [populated-dark.png](populated-dark.png) | [populated-light.png](populated-light.png) |
| Project defaults | B2 | [project-dark.png](project-dark.png) | [project-light.png](project-light.png) |
| Expanded loads and connection failure | B2 | [loads-dark.png](loads-dark.png) | [loads-light.png](loads-light.png) |
| Managed page | B4 | [managed-page-dark.png](managed-page-dark.png) | [managed-page-light.png](managed-page-light.png) |
| Managed source stack | B4 | [managed-dark.png](managed-dark.png) | [managed-light.png](managed-light.png) |
| Managed required load | B4 | [managed-loads-dark.png](managed-loads-dark.png) | [managed-loads-light.png](managed-loads-light.png) |
| Agent source stack, unmanaged | No exact mock; B4 structure | [source-dark.png](source-dark.png) | [source-light.png](source-light.png) |
| Project-inherited source stack, unmanaged | No exact mock; B4 structure | [inherited-dark.png](inherited-dark.png) | [inherited-light.png](inherited-light.png) |
| Unreported/no choices | No exact mock; B1 structure | [empty-dark.png](empty-dark.png) | [empty-light.png](empty-light.png) |
| Unavailable saved choice | No exact mock; B1 structure | [unavailable-dark.png](unavailable-dark.png) | [unavailable-light.png](unavailable-light.png) |
| No agents | No exact mock | [no-agents-dark.png](no-agents-dark.png) | [no-agents-light.png](no-agents-light.png) |
| Narrow 700pt window | No exact mock; B1 structure | [narrow-dark.png](narrow-dark.png) | [narrow-light.png](narrow-light.png) |
| Narrow collapsed loads and budget | No exact mock; B1 structure | [narrow-loads-dark.png](narrow-loads-dark.png) | [narrow-loads-light.png](narrow-loads-light.png) |
| Focused value popup | No exact mock; B1 grouped background | Pending | Pending |
| Focused load switch | No exact mock; B2 grouped background | Pending | Pending |

Recovered reference PNGs are in reference/. They are prior mock renders, not fresh app evidence. Before each capture or UI measurement, run /tmp/native-tools/screenlocked. If locked, do not capture or claim visual verification.


## Checks at f872dc41

- `scripts/dev/run-isolated.sh cx-cont-134 --build`: passed, Debug.
- `scripts/check-warnings.sh /tmp/native-dd/cx-cont-134/build.log`: no repository warnings.
- `scripts/tests/settings-regression.sh cx-cont-134`: three consecutive passes.
- `nice -n 10 swift test -j 4 --package-path Packages/TaskDefaults --filter 'TaskDefaultsTests|TaskInstructionInventoryTests'`: 8 passed.
- `nice -n 10 swift test -j 4 --package-path Packages/NativePolicy --filter 'OrganizationIdentityTests|NativePolicyTests|CelebrationManagedPolicyTests'`: 80 passed.
- `nice -n 10 swift test -j 4 --package-path Packages/Modes --filter 'ModeResolverTests|ModeInstructionsTests'`: 17 passed.
- `nice -n 10 swift test -j 4 --package-path Packages/ACP --filter 'NewSessionChoicesTests|ConfigChoicesTests'`: 20 passed.
- `nice -n 10 swift test -j 4 --package-path Packages/NativeCommands --filter KeyboardDocumentTests`: 5 passed.
- Strict Swift formatting on the five incremental files and `git diff --check`: passed.
- GitHub CI Debug, Release compile/warnings, iOS and release asset checks: passed.
- GitHub Nightly compile: passed. Size gate: failed, download 47.6 MB / 47.5 MB; installed 117.2 MB / 118 MB. No budget was raised.
- Local `scripts/check-ios.sh native/Settings/Plainly`: failed while checking app dependencies, including AutomationCenter, ExpeditionCenter, DurableHost+Updates and TerminalGhosttySection. No diagnostic names a NewTasks file. The separate CI iOS check passed; the local broad dependency check remains a limit.
- Pullfrog approved f872dc41 with no new issues; no unresolved review threads.

## Visual and interaction evidence

The Plainly switch was written with `defaults write dev.binbandit.native.dev.cx-cont-134 experiment.NativeSettingsPlainly -bool YES`. The running page was confirmed by its New Tasks scope controls, value-source buttons and context budget. Captures used inert fixtures only. Selecting Codex in these screenshots did not start a Codex session or any real agent session.

All images were captured through `drive.sh cx-cont-134 shot` while the screen was unlocked. The driver reported that other windows covered portions of the isolated window, so covered regions may be stale. Changed content was checked against the accessibility text; snapshots were retaken after presentation transitions settled. The app stayed in the background and was quit after each check.

Compared B1, B2 and B4 against the app in both appearances, including source stacks, aligned counts/controls, off names, error text, the single budget note and stacked narrow rows. Side-by-side images are `compare-{populated,project,loads,managed}-{dark,light}.png`. Exact fixture counts, the selected agent and the existing Workspace settings differ from the mock. The managed fixture has two managed values, so its scope correctly says "sets 2". The result says "allowed default", because the backend uses the allowed agent default rather than choosing a maximum permission level.

The requested focus-ring evidence is **blocked**: two pid-scoped `drive.sh cx-cont-134 key tab` events left `drive.sh cx-cont-134 focused` on the same navigation heading. No popup or switch focus was reached. Nothing was made frontmost, no global events were sent, and no simulated focus ring was substituted. Item 12 remains pending.

Visual coverage is **partial**, with coordinator design review still pending. There was no fresh before-build UI reproduction in this continuation; earlier review2 images retain the before evidence. The existing code changes for items 1-11 were retained and the remaining row/summary issues were corrected. Do not treat these captures as a design approval.
