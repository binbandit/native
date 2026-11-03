# Live test of PR #273

Status: blocked, not passed.

Revision: 6594db85855e85807ca4a73f0c03855c2072add0. Clean worktree when built. Isolated Debug instance cx-live273 on elara. Build passed with no repository warnings. Window 1250 x 900, light and dark. Sounds disabled. Display kept awake for the run. Screen unlocked and Swift Accessibility trust check returned trusted. Fixture projects only.

## Ranked findings

1. Blocking test prerequisite: the scoped driver exposes no AXWindow or window controls for the visible Native window. `tree --raw --frames` returned no elements; `focused` returned only `AXApplication "Native"`. `press "New Task in sample"` failed with `nothing matches`. The menu driver listed File and View menus, but File > New Task and New Task With did not change the visible Home screen. Reproduced before and after a clean isolated relaunch, in light and dark. This is an automation/accessibility blocker, not a confirmed composer regression. The existing sidebar-pull-requests test script explicitly recognizes an empty AX tree as a pending UI check.

No product defect was established. No keys were posted because Message keyboard focus could not be confirmed. No real agent session was started. There is no evidence for a live-test pass.

## Coverage

- Verified: isolated Debug build; no repository warnings; actual Native window screenshot rather than desktop; light and dark launch; muted launch arguments; no isolated crash report returned.
- Blocked: new task In my folder and On a new branch; long draft growth, scrolling and stable row; keyboard file and folder mentions; slash command; paste and drop attachment routing; Enter and Shift-Enter; Undo; mid-task agent/model change and real-model label; removable mode chip; queue, Remove and supported Send now; Stop retaining draft/request and queue; question and approval retaining draft; diff comment delivery to composer.
- No changed composer state was reached, so no composer-state mock comparison was possible. The Home launch screenshots have no supplied matching mock.

## Screenshots

- 01-launched.png: light launch, visible isolated Native window.
- 02-new-task.png: light, unchanged Home after scoped File > New Task.
- 03-relaunch-dark.png: clean relaunch, visible dark Native window.
- 04-no-new-task.png: dark, unchanged Home after scoped New Task With.

The fixture seed initially failed on its scratch local-origin Git LFS pre-push hook due to missing LFS objects. The local fixture push was completed with GIT_LFS_SKIP_PUSH=1, and seed then succeeded. Its package build changed NativeHost's resolved dependencies on disk after the app build; that generated change was reverted and was never part of the tested app binary.

The isolated app was quit immediately after the check. A rerun needs the visible isolated window to expose its controls through the authorized driver, or an explicitly authorized alternative driving method.
