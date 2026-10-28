# Open Folder placement review

Revision: `19418efaf`. Isolated Debug instance: `cx-open-folder-rework`, 1000 by 700, light and dark. Sidebar Next was enabled with a typed defaults value. Sound and status bar were disabled in this instance. No real session or system chooser was opened.

[Design HTML](open-folder-v2.html) and [spec](open-folder-v2-spec.md) supersede requests-1026 section 1. [Capture manifest](manifest.json). [Native state matrix](native-matrix.png).

The header uses SidebarSectionLabel and the existing small IconButton, with no new visual tokens. The footer action and its recents popover are removed. The common project picker ends with Open Folder…. The folder model and its existing tests are preserved.

| Changed state | Native light / dark | Matching mock light / dark | Comparison |
| --- | --- | --- | --- |
| rest | [light](rest-light.png) / [dark](rest-dark.png) | [light](mocks/rest-light.png) / [dark](mocks/rest-dark.png) | [light](compare-rest-light.png) / [dark](compare-rest-dark.png) |
| picker | [light](picker-light.png) / [dark](picker-dark.png) | [light](mocks/picker-light.png) / [dark](mocks/picker-dark.png) | [light](compare-picker-light.png) / [dark](compare-picker-dark.png) |
| empty | [light](empty-light.png) / [dark](empty-dark.png) | [light](mocks/empty-light.png) / [dark](mocks/empty-dark.png) | [light](compare-empty-light.png) / [dark](compare-empty-dark.png) |
| drop | [light](drop-light.png) / [dark](drop-dark.png) | [light](mocks/drop-light.png) / [dark](mocks/drop-dark.png) | [light](compare-drop-light.png) / [dark](compare-drop-dark.png) |
| blocked | [light](blocked-light.png) / [dark](blocked-dark.png) | [HTML state](open-folder-v2.html?only=blocked&theme=pair); final PNG refresh pending while locked | Pending final mock refresh |
| opening | [light](opening-light.png) / [dark](opening-dark.png) | [HTML state](open-folder-v2.html?only=opening&theme=pair); final PNG refresh pending while locked | Pending final mock refresh |
| hover | Real-surface capture pending | [light](mocks/hover-light.png) / [dark](mocks/hover-dark.png) | No supported driver input |
| touch | Real-surface capture pending | [light](mocks/touch-light.png) / [dark](mocks/touch-dark.png) | No supported driver input |

Additional unchanged recovery context: [failure light](failure-light.png), [failure dark](failure-dark.png), [Added/Undo light](added-light.png), [Added/Undo dark](added-dark.png). These retain the existing feedback design; the new header follows the rest mock above.

## Verification

- Debug build and repository warning check passed at this revision.
- Existing sidebar-folders integration checks passed: folder batches, aliases, files/packages, recents, Undo, drafts, navigation, cancellation and managed admission.
- FolderHistoryTests: 2 passed. FolderPolicyTests and PolicyCoverageTests: 9 passed.
- Strict Swift format lint and diff whitespace check passed.
- File menu still exposes Open Folder… with Command-O and Open Recent. The three project addresses use the same QuickEntryPicker captured here.
- Rest, picker, empty and drag feedback were compared side by side in light and dark. The plus aligns to the existing heading and control edges. Native chrome and the unchanged fixture transcript retain their current app rendering. Blocked and opening native captures were reviewed; their final mock PNG refresh was interrupted by screen locking.

## Remaining checks

Visual check pending. A separate coordinator design review is required before merge.

The driver cannot create pointer hover, an external folder drag or iPad touch. The drop capture is inert feedback, backed by the existing model checks; it does not prove an external drag interaction. The always-visible plus and existing dsHitTarget are retained for touch, but no iPad screenshot is claimed. Hover reuses unchanged IconButton styling. System chooser activation was not driven because the playtesting rules prohibit opening system pickers. The driver warned that Ghostty covered the window; captures visibly show the intended states and were corroborated by AX trees.
