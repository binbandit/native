# Celebrations visual check

Visual check done at `dd8d1f36823c50b2d446389816d4c8623652d296`, Debug, isolated instance `vc-104`.
Compared with Celebrations in `polish.html` and section 04 of `polish-spec.md`.
The design explicitly uses existing Settings primitives; catalogue totals are the real catalogue.

The Back failure was reproduced at `c401d3d9`: December at scrollbar 0.4275395033860045 returned to 0.
The fix keeps the scroll callback on the stable Settings screen and restores the saved offset after catalogue layout.
All 12 repeated round trips passed: light/dark, ordinary/Plainly, detail Back/Cmd-[/toolbar Back, and a manually scrolled bottom position.
December returns to exactly 0.4275395033860045 in ordinary Settings and 0.67576099210823 in Plainly.
Settings search from a detail to Diwali also passed in all four combinations.

| Before fix: after Back | Fixed: after Back, dark | Fixed: after Back, light |
| --- | --- | --- |
| ![](before-after-dark.png) | ![](fixed-after-dark.png) | ![](fixed-after-light.png) |

| Plainly, dark | Plainly, light |
| --- | --- |
| ![](back-restored-YES-dark.png) | ![](back-restored-YES-light.png) |

## Gallery

Each of the 21 states was recaptured and inspected in both appearances at 1440 x 900 points.

| State | Dark | Light |
| --- | --- | --- |
| page | ![](app-page-dark.png) | ![](app-page-light.png) |
| showing | ![](app-showing-dark.png) | ![](app-showing-light.png) |
| homeOnly | ![](app-homeOnly-dark.png) | ![](app-homeOnly-light.png) |
| skipped | ![](app-skipped-dark.png) | ![](app-skipped-light.png) |
| waiting | ![](app-waiting-dark.png) | ![](app-waiting-light.png) |
| failed | ![](app-failed-dark.png) | ![](app-failed-light.png) |
| empty | ![](app-empty-dark.png) | ![](app-empty-light.png) |
| yearHover | ![](app-yearHover-dark.png) | ![](app-yearHover-light.png) |
| rows | ![](app-rows-dark.png) | ![](app-rows-light.png) |
| overlaps | ![](app-overlaps-dark.png) | ![](app-overlaps-light.png) |
| detail | ![](app-detail-dark.png) | ![](app-detail-light.png) |
| style | ![](app-style-dark.png) | ![](app-style-light.png) |
| offline | ![](app-offline-dark.png) | ![](app-offline-light.png) |
| confirmation | ![](app-confirmation-dark.png) | ![](app-confirmation-light.png) |
| off | ![](app-off-dark.png) | ![](app-off-light.png) |
| pending | ![](app-pending-dark.png) | ![](app-pending-light.png) |
| menu | ![](app-menu-dark.png) | ![](app-menu-light.png) |
| search | ![](app-search-dark.png) | ![](app-search-light.png) |
| noMatches | ![](app-noMatches-dark.png) | ![](app-noMatches-light.png) |
| unavailableSelections | ![](app-unavailableSelections-dark.png) | ![](app-unavailableSelections-light.png) |
| unavailableDetail | ![](app-unavailableDetail-dark.png) | ![](app-unavailableDetail-light.png) |

## Additional checks

| State | Dark | Light |
| --- | --- | --- |
| narrow-page | ![](app-narrow-page-dark.png) | ![](app-narrow-page-light.png) |
| narrow-detail | ![](app-narrow-detail-dark.png) | ![](app-narrow-detail-light.png) |
| plainly-detail-fixed | ![](app-plainly-detail-fixed-dark.png) | ![](app-plainly-detail-fixed-light.png) |
| plainly-search | ![](app-plainly-search-dark.png) | ![](app-plainly-search-light.png) |
| pending-expanded | ![](app-pending-expanded-dark.png) | ![](app-pending-expanded-light.png) |
| offline-detail | ![](app-offline-detail-dark.png) | ![](app-offline-detail-light.png) |
| unavailable-disabled | ![](app-unavailable-disabled-dark.png) | ![](app-unavailable-disabled-light.png) |
| managed-off | ![](app-managed-off-dark.png) | ![](app-managed-off-light.png) |

Unavailable selected rows and detail switches can turn off, then remain disabled. Offline icon switches are disabled while Home remains available. Managed-off hides the chooser and its search entries. Row accessibility toggle changes the selection without opening details; opening the row and returning keeps the filter. Physical switch hit-testing and row Space/Return are not claimed: the background driver cannot focus those rows, and pointer clicks are prohibited by the shared-Mac rules.

The initial review's popup and bulk Undo evidence remains at [80c9c297](https://github.com/binbandit/native/blob/80c9c297caeefde443c48bfa5c6f6823b7d017ec/feat-celebrations-settings/README.md).

Validation: isolated Debug build and repository warning check passed; 70 targeted AppAppearance tests and 2 managed-policy tests passed; strict lint passed on all changed Swift files. The local iPad type-check is blocked by unchanged `native/KeepAwake/Engine/PowerState.swift` importing `IOKit.ps`.
