# Inline diff comments verification

Revision: `a8b4ba6b8bb23e1a5dcb44e2845c6b4e7750804f`. All C1-C13 light and dark state captures use this PR revision. C14 adds the locally held recovery state; C13 is its layout reference because no dedicated mock was supplied. The normal app Haiku checks were captured before final visual polish; the queued-edit capture uses this revision.

Native is on the left of every comparison; the approved HTML mock is on the right. The changed components use the live model and views. The inert fixture uses a reference frame around them; the real Haiku capture shows the normal app frame. Screenshots were taken while unlocked through the isolated instance driver. Covered-window warnings were emitted by the driver; captured content was inspected.

## Behavior

- Verified pointer Add, newline with Return, Add with Command-Return, Escape/cancel retention, and reopening the same unfinished editor.
- Verified two files collected and submitted to Claude Code on Haiku 5.5 at low effort as one transcript message, with both snapshots and bodies. The agent replied OK and the accepted draft cleared.
- Verified a saved comment and an unfinished comment survive `/clear`, then add and send together from the fresh conversation. No working prompt was sent by clearing.
- The model harness passed three consecutive runs after the queue changes, then passed again on the final visual revision, including acknowledged queue edits and missing-item retention. Packet recovery compares parsed contents. Older evidence with the same comment identity does not acknowledge edited content.
- Package checks passed: 23 ACP quote/comment/range tests, 9 policy/coverage tests, and 16 command/keyboard tests. Strict lint passed for changed Swift files.
- The complete iOS CI build passed on the initial revision. Current-head iOS CI is rerunning. The local folder-only checker encountered shared resolver diagnostics; it is not the platform acceptance evidence.
- Release and Nightly compiled at 9f1ab9dc and stayed within every size budget: Release download 47.9 MB, Nightly download 48.0 MB, both installed 117.6 MB. Final-revision checks are recorded in the PR status. No budget was changed.

## Captured states

| State | Native dark | Mock dark | Comparison dark | Native light | Mock light | Comparison light |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | [Native](captures/C1-dark.png) | [Mock](mocks/C1-dark.png) | [Side by side](comparisons/C1-dark.png) | [Native](captures/C1-light.png) | [Mock](mocks/C1-light.png) | [Side by side](comparisons/C1-light.png) |
| C2 | [Native](captures/C2-dark.png) | [Mock](mocks/C2-dark.png) | [Side by side](comparisons/C2-dark.png) | [Native](captures/C2-light.png) | [Mock](mocks/C2-light.png) | [Side by side](comparisons/C2-light.png) |
| C3 | [Native](captures/C3-dark.png) | [Mock](mocks/C3-dark.png) | [Side by side](comparisons/C3-dark.png) | [Native](captures/C3-light.png) | [Mock](mocks/C3-light.png) | [Side by side](comparisons/C3-light.png) |
| C4 | [Native](captures/C4-dark.png) | [Mock](mocks/C4-dark.png) | [Side by side](comparisons/C4-dark.png) | [Native](captures/C4-light.png) | [Mock](mocks/C4-light.png) | [Side by side](comparisons/C4-light.png) |
| C5 | [Native](captures/C5-dark.png) | [Mock](mocks/C5-dark.png) | [Side by side](comparisons/C5-dark.png) | [Native](captures/C5-light.png) | [Mock](mocks/C5-light.png) | [Side by side](comparisons/C5-light.png) |
| C6 | [Native](captures/C6-dark.png) | [Mock](mocks/C6-dark.png) | [Side by side](comparisons/C6-dark.png) | [Native](captures/C6-light.png) | [Mock](mocks/C6-light.png) | [Side by side](comparisons/C6-light.png) |
| C7 | [Native](captures/C7-dark.png) | [Mock](mocks/C7-dark.png) | [Side by side](comparisons/C7-dark.png) | [Native](captures/C7-light.png) | [Mock](mocks/C7-light.png) | [Side by side](comparisons/C7-light.png) |
| C8 | [Native](captures/C8-dark.png) | [Mock](mocks/C8-dark.png) | [Side by side](comparisons/C8-dark.png) | [Native](captures/C8-light.png) | [Mock](mocks/C8-light.png) | [Side by side](comparisons/C8-light.png) |
| C9 | [Native](captures/C9-dark.png) | [Mock](mocks/C9-dark.png) | [Side by side](comparisons/C9-dark.png) | [Native](captures/C9-light.png) | [Mock](mocks/C9-light.png) | [Side by side](comparisons/C9-light.png) |
| C10 | [Native](captures/C10-dark.png) | [Mock](mocks/C10-dark.png) | [Side by side](comparisons/C10-dark.png) | [Native](captures/C10-light.png) | [Mock](mocks/C10-light.png) | [Side by side](comparisons/C10-light.png) |
| C11 | [Native](captures/C11-dark.png) | [Mock](mocks/C11-dark.png) | [Side by side](comparisons/C11-dark.png) | [Native](captures/C11-light.png) | [Mock](mocks/C11-light.png) | [Side by side](comparisons/C11-light.png) |
| C12 | [Native](captures/C12-dark.png) | [Mock](mocks/C12-dark.png) | [Side by side](comparisons/C12-dark.png) | [Native](captures/C12-light.png) | [Mock](mocks/C12-light.png) | [Side by side](comparisons/C12-light.png) |
| C13 | [Native](captures/C13-dark.png) | [Mock](mocks/C13-dark.png) | [Side by side](comparisons/C13-dark.png) | [Native](captures/C13-light.png) | [Mock](mocks/C13-light.png) | [Side by side](comparisons/C13-light.png) |

## Normal app checks

[Two-file packet sent to Haiku](captures/real-haiku-sent-dark.png)

[Unfinished editor retained after a fresh conversation](captures/real-fresh-conversation-editor-dark.png)

All 26 final-revision state captures were refreshed after the screen unlocked, then compared side by side with the approved mock. The earlier normal-app captures document the real Haiku packet and fresh-conversation checks. The final native host queue edit was also checked with the scripted agent: queue one packet, reopen with Up, change the message (including a trailing newline), save, observe the owner-confirmed queue contents, and verify the field clears.

Visual check pending. A separate design review must approve the PR before merging.

## Review regression checks

- `HostQueueUpdateTests` passes both removal and drain races after a client snapshot.
- `scripts/tests/diff-comments.sh cx-build-diff-comments` passes held-packet persistence, edited held packets, rejection after lifting a hold, empty legacy responses, editor-only unsent recovery, text plus editor recovery, normalized message clearing and the existing draft checks.
- `scripts/tests/task-workspace.sh cx-build-diff-comments` passes candidate disconnection during configuration with source editors retained.
- `scripts/tests/droid-change-agent.sh cx-build-diff-comments` passes committed editor/delivery transfer and its existing failure/reconnection checks.
- Strict lint and isolated Debug compilation pass with no repository warnings.

| Additional state | Native dark | Native light | Layout reference |
| --- | --- | --- | --- |
| C14: locally held packet, recovery copy retained | [Dark](captures/C14-dark.png) | [Light](captures/C14-light.png) | C13 [dark](comparisons/C14-dark.png), [light](comparisons/C14-light.png); layout reference only |

[Owner-confirmed queue edit in the normal app](captures/real-queue-edit-dark.png). The scripted agent echoes fixture metadata; all IDs shown there are generated fixture IDs. The account sidebar is collapsed.
