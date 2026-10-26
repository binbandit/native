Current build: 1182d7dd, Debug, cx-redo-164. Fixture content only. Separate coordinator design review pending.

No separate plugin mock was required by the second design review. The plugin rows use session-top.html #T; pane and settings states reuse the named shared components. Terminal is Off in these captures to avoid exposing runtime paths. The sidebar and status bar are cropped from published shots.

| State | Light screenshot | Dark screenshot | Matching mock or existing pattern |
| --- | --- | --- | --- |
| Long title, working and failed facts, keyboard highlight | [light](shots/well-highlight-light.png) | [dark](shots/well-highlight-dark.png) | session-top.html #T |
| Long title in docked pane, status and Close | [light](shots/side-pane-light.png) | [dark](shots/side-pane-dark.png) | Shared SessionToolsSidePanel |
| Narrow pane, long header, status and Close | [light](shots/narrow-pane-light.png) | [dark](shots/narrow-pane-dark.png) | Shared SessionToolsShade |
| Default-Off Runbook, long summary and attribution beside built-ins | [light](shots/settings-off-light.png) | [dark](shots/settings-off-dark.png) | Shared Task Tools settings |
| Runbook enabled | [light](shots/settings-on-light.png) | [dark](shots/settings-on-dark.png) | Shared Task Tools settings |
| Runbook command registered | [light](shots/command-registered-light.png) | [dark](shots/command-registered-dark.png) | Shared Keyboard shortcuts settings |
| Enabled Runbook row highlighted | [light](shots/enabled-well-light.png) | [dark](shots/enabled-well-dark.png) | session-top.html #T |
| Runbook opened with Space | [light](shots/enabled-pane-light.png) | [dark](shots/enabled-pane-dark.png) | Shared SessionToolsSidePanel |
| Failed Notes over conversation | [light](shots/overlay-pane-light.png) | [dark](shots/overlay-pane-dark.png) | Shared SessionToolsShade |
| Live revocation of an open side pane, space reclaimed | [light](shots/revoked-side-light.png) | [dark](shots/revoked-side-dark.png) | Conversation with no pane |
| Revoked tools removed from well | [light](shots/revoked-well-light.png) | [dark](shots/revoked-well-dark.png) | session-top.html #T |
| Revoked command removed | [light](shots/command-removed-light.png) | [dark](shots/command-removed-dark.png) | Shared Keyboard shortcuts settings |
| Live revocation of an open overlay | [light](shots/revoked-overlay-light.png) | [dark](shots/revoked-overlay-dark.png) | Conversation with no pane |
| Runbook switched Off again | [light](shots/settings-disabled-light.png) | [dark](shots/settings-disabled-dark.png) | Shared Task Tools settings |
| Off Runbook absent from well | [light](shots/off-well-light.png) | [dark](shots/off-well-dark.png) | session-top.html #T |
| Keyboard opens the Dev page | [light](shots/back-page-light.png) | [dark](shots/back-page-dark.png) | session-top.html #T |
| Escape returns from page to tools | [light](shots/back-tools-light.png) | [dark](shots/back-tools-dark.png) | session-top.html #T |

Mock references: [#T light](mocks/mock-tools-light.png), [#T dark](mocks/mock-tools-dark.png).

Keyboard limitation: the inactive background instance has no focused task context in the View menu. View > Tools and Command-I entry are unverified. The well is opened through its AX button, then its arrow keys, Return, Space and Escape are exercised. Keyboard Shortcuts supplies independent evidence of command registration and removal; it does not prove menu activation or Off shortcut suppression.

The capture driver can report occlusion by another app. Screenshots are inspected against their AX states; no foreground activation is used.

[Verification results, exact limits and follow-ups](verification.txt).

Side-by-side review sheets: [sheet 0](comparison-0.png), [sheet 1](comparison-1.png), [sheet 2](comparison-2.png), [sheet 3](comparison-3.png), [sheet 4](comparison-4.png).

PR #205 remains open: the final-head Nightly update archive exceeded its budget,
and two confirmed Pullfrog findings remain unresolved (close-hook delivery on
plugin removal and overflow of a many-tools list). See verification.txt for exact
size figures and finding links. Work stopped under the job's size-budget rule.
