# Celebration settings visual check

Revision: fb30a626cb91bb6a8c5957b8d2656c72454484a1. Isolated Debug instance vc-104, 1440 by 900 points.

All preview captures use inert fixtures. The current Settings primitives intentionally differ from the Plainly styling in the mock. Catalogue counts follow real data.

## Blocking finding

From the page, choose December in the year strip, open Hanukkah, then use Back to Celebrations or Cmd-[. The catalogue returns to its top instead of December. Reproduced twice on the unchanged PR revision. The main scrollbar changes from 0.4275395 to 0.

| Before opening details | Detail | After Back |
| --- | --- | --- |
| ![December](navigation-before-dark.png) | ![Hanukkah](navigation-detail-dark.png) | ![Returned to top](navigation-after-dark.png) |

## Preview states

| State | Dark | Light |
| --- | --- | --- |
| page | ![page dark](app-page-dark.png) | ![page light](app-page-light.png) |
| showing | ![showing dark](app-showing-dark.png) | ![showing light](app-showing-light.png) |
| homeOnly | ![homeOnly dark](app-homeOnly-dark.png) | ![homeOnly light](app-homeOnly-light.png) |
| skipped | ![skipped dark](app-skipped-dark.png) | ![skipped light](app-skipped-light.png) |
| waiting | ![waiting dark](app-waiting-dark.png) | ![waiting light](app-waiting-light.png) |
| failed | ![failed dark](app-failed-dark.png) | ![failed light](app-failed-light.png) |
| empty | ![empty dark](app-empty-dark.png) | ![empty light](app-empty-light.png) |
| yearHover | ![yearHover dark](app-yearHover-dark.png) | ![yearHover light](app-yearHover-light.png) |
| rows | ![rows dark](app-rows-dark.png) | ![rows light](app-rows-light.png) |
| overlaps | ![overlaps dark](app-overlaps-dark.png) | ![overlaps light](app-overlaps-light.png) |
| detail | ![detail dark](app-detail-dark.png) | ![detail light](app-detail-light.png) |
| style | ![style dark](app-style-dark.png) | ![style light](app-style-light.png) |
| offline | ![offline dark](app-offline-dark.png) | ![offline light](app-offline-light.png) |
| confirmation | ![confirmation dark](app-confirmation-dark.png) | ![confirmation light](app-confirmation-light.png) |
| off | ![off dark](app-off-dark.png) | ![off light](app-off-light.png) |
| pending | ![pending dark](app-pending-dark.png) | ![pending light](app-pending-light.png) |
| menu | ![menu dark](app-menu-dark.png) | ![menu light](app-menu-light.png) |
| search | ![search dark](app-search-dark.png) | ![search light](app-search-light.png) |
| noMatches | ![noMatches dark](app-noMatches-dark.png) | ![noMatches light](app-noMatches-light.png) |
| unavailableSelections | ![unavailableSelections dark](app-unavailableSelections-dark.png) | ![unavailableSelections light](app-unavailableSelections-light.png) |
| unavailableDetail | ![unavailableDetail dark](app-unavailableDetail-dark.png) | ![unavailableDetail light](app-unavailableDetail-light.png) |

The menu preview starts at its trigger. The pending preview initially shows the catalogue; unavailable rows are visible in the rows and unavailable-selection previews.
