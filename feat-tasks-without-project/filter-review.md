# Filtered No project follow-up

PR #217, design feedback: [changes required](https://github.com/binbandit/native/pull/217#issuecomment-6465267418).

Before: `a770a7496dc757e31f9a516430d9fad478fce148`, clean worktree. After: `4224fb03c357d0be7c10a70154c021e7086277e3`, clean worktree. Isolated Debug instance: `cx-fix-217`. Offline fixture agent, signed-out GitHub fixture, sounds disabled.

## Reproduction

With All in view on, start an idle No project task through New Task With > Fixture. Open the Tasks context menu and select Filter Tasks > Needs you. The existing task disappears, but the No project group remains Expanded and says "Start a task here. A folder is optional."

[Fresh before capture, dark](filter-before-dark.png). The original design review also records this in both appearances.

## Change

ProjectList now passes isFiltered and hasNoMatches to NoProjectTaskGroup. The group uses the same expansion binding and "No matching tasks" note as ordinary project groups, and suppresses its first-task invitation while narrowing. Added paired previews for empty and unmatched states.

## Captures pending

The screen locked between the successful fixed build and its UI verification. `/tmp/native-tools/screenlocked` reported `locked`; the instance was quit. No after screenshots were taken and no post-fix visual or interaction pass is claimed. Existing approved-state captures remain unchanged.

| State to capture | Appearance | Design reference |
| --- | --- | --- |
| Existing idle task hidden by Needs you, group collapsed with No matching tasks | Light and dark | Existing ProjectSection filtered-empty treatment and AllInViewProjectGroup preview; no separate filtered mock was supplied |
| Clear the filter and restore the existing task | Light and dark | [Task/sidebar mock](mock-n4-light.png), [dark](mock-n4-dark.png) |
| Genuinely empty unfiltered group retains its invitation | Light and dark | Existing NoProjectTaskGroup empty state and [Home direction](mock-n2-light.png), [dark](mock-n2-dark.png) |

Repeat in both default and All in view sidebars. Turn Labs switches on using `defaults write dev.binbandit.native.dev.cx-fix-217 experiment.NativeSidebarNext -bool YES` (and NativeHomeNext/NativeComposerNext), not launch argument text. Launch using `scripts/dev/run-isolated.sh cx-fix-217 -- -sounds.enabled NO`, the isolated fixture plugins and `-gitHubAccountFixture signedOut`. Check screen lock before measurements/captures and quit immediately afterward.

Visual check pending

## Validation at 4224fb03

- `scripts/dev/run-isolated.sh cx-fix-217 --build`: passed.
- `scripts/check-warnings.sh /tmp/native-dd/cx-fix-217/build.log`: zero repository warnings; only Xcode's App Intents metadata notice.
- `swift format lint --strict native/NoProject/NoProjectTaskGroup.swift native/Views/Sidebar/ProjectList.swift`: passed.
- `git diff --check`: passed.
- `scripts/tests/no-project.sh cx-fix-217`: 14 model tests passed on three consecutive runs (34.470s, 34.885s, 34.368s).
- CI app build and changed Swift lint passed. Remaining CI/review checks were still running at this evidence update.
- Post-fix UI status: blocked by screen lock. Before reproduction was observed in the running app; after behavior and visual comparison remain pending.
