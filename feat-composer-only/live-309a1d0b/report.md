Live test: blocked

Revision: 309a1d0be94d09106e5d4d03249e408be548bf00. Clean worktree, fetched PR head, freshly built isolated Debug instance cx-live273 on elara. No product code changed.

Ranked findings:
1. Test blocker: the visible app window exposes no accessibility controls through the required pid-scoped driver. Initial, retry and final trees are empty; focused reports AXApplication Native. Accessibility trust reports trusted and the screen reports unlocked. The window is visibly rendered in both screenshots. Cause is unconfirmed; this does not establish a composer regression.

Stopped under the brief's two-minute accessibility cutoff instruction, without further investigation or key events. The launch record is 2026-11-03T10:46:46Z; the final blocked record is 2026-11-03T10:49:17Z (including command/wait overhead). The instance was then quit. Display sleep prevention and sound muting were enabled.

Build: scripts/dev/run-isolated.sh cx-live273 --build passed. scripts/check-warnings.sh /tmp/native-dd/cx-live273/build.log reported no repository warnings.

Not exercised: new task in the folder/new branch; long-draft sizing/scrolling and fixed row; file/folder @ keyboard completion; slash command; paste/drop attachment; Enter/Shift-Enter; Undo; agent/model changes and real model label; mode chip/removal; queue/Remove/Send now; Stop retaining request/queue; questions/approvals retaining draft; diff comment insertion. No real agent task was started. No pass claim can be made.

Screenshots:
- 01-launched.png: rendered startup window, dark appearance. Reference: real startup state; no mock supplied for this live test.
- 03-blocked.png: rendered window at final blocked check, dark appearance. Reference: real startup state; no mock supplied for this live test.

Follow-up: rerun the requested live matrix once pid-scoped accessibility exposes the window's controls. No code diagnosis or fix attempted, as requested.
