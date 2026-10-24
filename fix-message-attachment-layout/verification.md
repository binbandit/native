# PR 106 visual check

- Before: `d7a52f01c2fa8e6e790f57c99b74e802abe3febb` (main), clean tree.
- After: `b18a9896d5a8ce43c8f4d203f1eab349c0c29bd0`, clean tree.
- Environment: macOS 27.2, Xcode 27.1 (27A9275), isolated Debug instance `vc-106`.
- Surface: real transcript replayed by a local fixture ACP plugin and the existing in-app artifact viewer. No model calls.
- Windows: 1000 x 800 and 520 x 800 points. Screen unlocked before every capture and measurement. No window activation.
- Standard: `defaults write dev.binbandit.native.dev.vc-106 experiment.bubbles -bool NO`.
- Bubbles: the same setting with `YES`. A launch argument is a string and does not enable this Boolean experiment.
- Appearance: `-appearance.mode light` and `-appearance.mode dark`.

## Results

| Claim | Status | Evidence |
| --- | --- | --- |
| User attachments form a trailing-aligned group above the prompt | Verified | Before images show short file chips beside tall images. After images show matching 160 x 96 tiles; Bubbles aligns to the bubble body inside the tail. |
| Mixed attachments preserve order and wrap | Verified | 2, 3 and 6 fixtures in both styles and appearances; 520-point window wraps six into three rows of two without clipping. |
| Single images preserve their shape | Verified | A 960 x 320 source displays at 280 x 93 points, and a 320 x 960 source at approximately 47 x 140 points. |
| File details remain legible | Verified | Middle truncation preserves the extension; 2 KB, 8 KB, 15 bytes, Zero KB and Size unavailable render without clipping. |
| Unavailable images use a file tile | Verified | Invalid image data shows the photo symbol and filename instead of a blank thumbnail. |
| Pointer-equivalent tile activation | Verified | `drive.sh vc-106 press 'Open Diagram-wide.png'` and `press 'Open notes.txt'` open the existing viewer with the expected image or text. |
| Escape closes the viewer | Verified | `drive.sh vc-106 key escape`, followed by waiting for Close Viewer to disappear. |
| Tab / Space activation | Partial | The background app keeps focus in the composer. Tab inserts a tab and Shift-Tab stays in the editor. A temporary driver action setting AXFocused on the tile returned success but did not move focus. The driver was restored; no window was made active. No keyboard activation pass is claimed. |

All 28 layout captures were inspected. No visual source changes were needed. The supplied polish spec covers Run, account switching, toast Undo and Celebrations, with no attachment mock; this check uses the PR's acceptance list and the actual before rendering.

## Validation

- `scripts/dev/run-isolated.sh vc-106 --build`
- `scripts/check-warnings.sh /tmp/native-dd/vc-106/build.log`: no warnings from repository files.
- `nice -n 10 swift test -j 4 --filter MessageAttachmentReplayTests` in `Packages/ACP`: 6 passed.
- `nice -n 10 swift test -j 4 --filter EchoArtifactTests` in `Packages/NativeHost`: 2 passed.
- `swift format lint --strict` on the 13 changed Swift files: passed.
- `git diff --check`: passed.
