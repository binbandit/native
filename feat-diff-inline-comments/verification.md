# Inline diff comments verification

Revision: `dce92e1035c42a3f53d5cc77c90f649af7c2f60a`. All C1-C15 light and dark state captures use this revision after merging main. C14 adds local waiting and C15 adds editing that same queued packet; C13 is their layout reference because no dedicated mock was supplied. Earlier interactive captures at `361e6eef` document pointer Save and Return to Draft. The normal app Haiku checks were captured before final visual polish.

Native is on the left of every comparison; the approved HTML mock is on the right. The changed components use the live model and views. The inert fixture uses a reference frame around them; the real Haiku capture shows the normal app frame. Screenshots were taken while unlocked through the isolated instance driver. Covered-window warnings were emitted by the driver; captured content was inspected.

## Behavior

- Verified pointer Add, newline with Return, Add with Command-Return, Escape/cancel retention, and reopening the same unfinished editor.
- Verified two files collected and submitted to Claude Code on Haiku 5.5 at low effort as one transcript message, with both snapshots and bodies. The agent replied OK and the accepted draft cleared.
- Verified a saved comment and an unfinished comment survive `/clear`, then add and send together from the fresh conversation. No working prompt was sent by clearing.
- The model harness passed three consecutive runs after the queue changes, then passed again on the final visual revision, including acknowledged queue edits and missing-item retention. Packet recovery compares parsed contents. Older evidence with the same comment identity does not acknowledge edited content.
- Package checks passed: 24 ACP quote/comment/range/recovery tests, 9 policy/coverage tests, and 16 command/keyboard tests. Strict lint passed for changed Swift files.
- The complete CI matrix, including iOS, passed at `a8b4ba6b`. Current-head CI is rerunning. The local folder-only checker encountered shared resolver diagnostics; it is not the platform acceptance evidence.
- Release compiled at `a8b4ba6b` within budget. Nightly compiled at `361e6eef`, but its ZIP is 48,014,278 bytes against 48,000,000: over by 14,278 bytes. Installed size is 117.7 MB of 118 MB. This is an unresolved landing blocker; integrated-head Release/Nightly size checks remain pending. No budget, packaging, signing or release setting was changed.

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

All 30 final-revision state captures were refreshed after the screen unlocked, then compared side by side with their supplied mock or the explicitly labelled C13 layout reference. The earlier normal-app captures document the real Haiku packet and fresh-conversation checks. The final native host queue edit was also checked with the scripted agent: queue one packet, reopen with Up, change the message (including a trailing newline), save, observe the owner-confirmed queue contents, and verify the field clears.

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
| C15: editing the owning local queued packet | [Dark](captures/C15-dark.png) | [Light](captures/C15-light.png) | C13 [dark](comparisons/C15-dark.png), [light](comparisons/C15-light.png); layout reference only |

## Local queue edit UI checks

At `361e6eef`, the actual pointer Save control was enabled after editing a local queued comment and saved the edited words. Opening Edit Message again, pressing Escape, and choosing Return to Draft restored both comments and the edited body, with no queued copy or recovery banner remaining. Both themes were checked.

| State | Dark | Light | Mock |
| --- | --- | --- | --- |
| Saved local edit | [Capture](captures/local-edit-saved-dark.png) | [Capture](captures/local-edit-saved-light.png) | No dedicated mock; C13 layout reference |
| Returned to draft after cancelling edit | [Capture](captures/local-returned-dark.png) | [Capture](captures/local-returned-light.png) | C4 collected-draft layout reference |

The integrated-head agent-model harness also verifies that selecting another agent/model and Undo move unfinished editors and unresolved delivery ownership together with the visible draft. ACP, policy, keyboard, host queue, diff-comment model, workspace and agent-handoff checks pass after integration. Pullfrog approved `361e6eef` and resolved all six findings; the integrated head also has passing Pullfrog approval. macOS build and lint CI pass; iOS, Linux and package CI are still running.

[Owner-confirmed queue edit in the normal app](captures/real-queue-edit-dark.png), captured at `361e6eef`. The scripted agent echoes generated fixture IDs and the account sidebar is collapsed.

## Visual comparison context

The fixture retains Native's shared sidebar, diff context folding and platform composer material, which differ from the HTML frame. The new controls and source snapshots are rendered by their production views. The C7 earlier-version state adds a real changed line to invalidate the snapshot; it therefore has one extra diff row. These captures are review evidence, not a design approval.
