# PR 100 visual check

Revision: 11b8abe94410cc6e4af930ac97e1c59148c25ea7, clean working tree. All screenshots and the archive/Hosts Cmd-Z checks were repeated after merging main at 004b345e. Package tests and lint passed again.
Final integration revision: ae03bfce41b9bb09e4342883c5e8124ddf361b58. Its additional main merge contains only release-packaging changes. `git diff 11b8abe9 ae03bfce -- native Packages Companion native.xcodeproj Config Runtime` is empty, so the screenshots cover identical app inputs. The isolated build, warning gate, 22 Undo tests, lint and diff checks passed again at ae03bfce.

Environment: macOS 27.2 (26B5091g), isolated Debug instance vc-100.
Reference: supplied polish.html item 03 and polish-spec.md section 03. The self-contained mock-toast.html preserves the supplied toast CSS, tokens, state definitions and fixture content, with local font references embedded. It is a mock source artifact, not a screenshot of the app.

## Observed on the running app

- Rest, Hover, Pressed, Keyboard focus, One line, Without Cmd-Z, Three lines and iPad appearance captured together in light and dark through the existing undo-toast gallery. Text does not clip, the action fills the trailing edge, and close/focus treatments match the written spec. The focus close button follows the written spec rather than the HTML's omission.
- Standard task layout checked at 1440 x 900 dark and 1000 x 850 light. The initial integrated revision f62c22f8 left 20 points between visible toast and composer. c95501a4 excludes the shared 8-point top margin from measurement, leaving the specified 12 points. The Task Tools layout was also captured at 1000 x 850 in both appearances, after setting its Boolean preference with defaults write. A launch-argument attempt had left this gate off; those captures were replaced.
- Archive: named Undo restores the task. Dismiss removes the toast. Escape leaves it in place. A newer composer edit removes the Cmd-Z hint while keeping the toast's direct Undo effective. An untouched offer expires after five seconds.
- Cmd-Z archive check used the existing long-session scripted ACP plugin in the normal app model. Edit changed from Undo Archive Task to Redo Archive Task after Cmd-Z, the archived row returned, and its toast disappeared. No real model session was used.
- Hosts: removal stays anchored in the Settings pane above the status bar in both appearances. The Edit menu offers Undo Remove Host; Cmd-Z restores it. Removing two hosts replaces the first toast; Undo restores the second, then Cmd-Z restores the first in order.
- Accessibility exposes one toast element with named Undo and Dismiss actions; both were exercised through drive.sh.
- No instance crash reports. The screen was unlocked before every capture. Captures were checked against the live labels after animation settled; the driver reported covered windows, so stale captures were discarded. The final dark Task Tools capture used an uncovered window at x=2700.

One five-second Hosts confirmation wait timed out in the batch. Repeating the same actions from a fresh launch with a fifteen-second wait passed in both appearances. No app crash was reported.

## Scope limits

The hover, pressed, keyboard focus and iPad appearances use the existing inert gallery. Physical pointer hover, keyboard focus retention, reduced-motion animation and iPad swipe dismissal were not driven: the permitted Mac driver has no pointer/touch gesture API, its background instance cannot prove active-app focus behavior, and no system accessibility settings were changed. The three lifetime tests cover holding, resumption and the three-second minimum. These are runtime coverage limits, not observed failures. No pre-PR application build was run; the visual regression found during this check was reproduced at f62c22f8 before the spacing correction.

All screenshots use source-defined fixture content. The /fixture/native label and account/host names are fictional fixture values.

## Commands

- scripts/dev/run-isolated.sh vc-100 --build
- scripts/check-warnings.sh /tmp/native-dd/vc-100/build.log
- nice -n 10 swift test -j 4 --package-path Packages/Undo --filter 'UndoHistoryTests|UndoableActionTests|UndoToastLifetimeTests' (22 tests passed)
- swift format lint --strict on all 17 changed Swift files
- defaults write dev.binbandit.native.dev.vc-100 experiment.session-tools -bool YES (deleted after Task Tools checks)
- scripts/check-ios.sh native/DesignSystem/Patterns/UndoToastBottomInset.swift (passed, including DesignSystem dependencies)
- git diff --check
- scripts/dev/run-isolated.sh vc-100 --no-build -- -nativeSidebarFixture undo-toast -nativeWindowFrame '50 50 900 1250' -appearance.mode dark
- scripts/dev/run-isolated.sh vc-100 --no-build -- -nativeSidebarFixture busy -nativeWindowFrame '50 700 1440 900' -appearance.mode dark
- scripts/dev/run-isolated.sh vc-100 --no-build -- -nativeSidebarFixture busy -nativeWindowFrame '50 700 1000 850' -appearance.mode light
- scripts/dev/run-isolated.sh vc-100 --no-build -- -NativeHostsFixtures all -nativeWindowFrame '50 700 1100 900' -appearance.mode light (and dark)
- All actions used scripts/dev/drive.sh vc-100; each scenario ended with run-isolated.sh vc-100 --quit.
