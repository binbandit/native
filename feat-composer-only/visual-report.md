# Composer removal visual evidence

Visual check pending

These are real SwiftUI preview renders from revision `870fc0ce1`, captured while the screen was unlocked. They are preliminary: the final revision restores host-specific text insets and typography. No live app was driven on this Mac.

The paired Quick Entry preview entered a focus feedback loop and its render harness was stopped. The following attempt found the screen locked. Final single-appearance rendering, comparison with the design mocks in both appearances, and live testing on the build Mac remain required before merge.

No exact mock images were supplied for this removal job. The reference is the Part A-C implementation on main and the composer specification. A rendered main baseline could not be captured before the screen locked. Each row below therefore records the mock comparison as pending.

| Changed state | Light capture | Dark capture | Matching mock/reference |
| --- | --- | --- | --- |
| Composer field - Empty, draft, attachments and growing text | [light](preliminary-870fc0ce1/preview-0-light.png) | [dark](preliminary-870fc0ce1/preview-0-dark.png) | Part A-C main baseline; comparison pending |
| Composer field - Narrow, working and labelled stopping | [light](preliminary-870fc0ce1/preview-1-light.png) | [dark](preliminary-870fc0ce1/preview-1-dark.png) | Part A-C main baseline; comparison pending |
| Composer field - File and command lists | [light](preliminary-870fc0ce1/preview-2-light.png) | [dark](preliminary-870fc0ce1/preview-2-dark.png) | Part A-C main baseline; comparison pending |
| Composer field - Attachment failure | [light](preliminary-870fc0ce1/preview-3-light.png) | [dark](preliminary-870fc0ce1/preview-3-dark.png) | Part A-C main baseline; comparison pending |
| Composer field - Completion above the caret | [light](preliminary-870fc0ce1/preview-4-light.png) | [dark](preliminary-870fc0ce1/preview-4-dark.png) | Part A-C main baseline; comparison pending |
| Composer pending - Working queue and stopped queue | [light](preliminary-870fc0ce1/preview-5-light.png) | [dark](preliminary-870fc0ce1/preview-5-dark.png) | Composer specification; no supplied mock; review pending |
| Composer pending - Question keeps the draft visible | [light](preliminary-870fc0ce1/preview-6-light.png) | [dark](preliminary-870fc0ce1/preview-6-dark.png) | Composer specification; no supplied mock; review pending |
| Composer pending - Approval keeps the draft visible | [light](preliminary-870fc0ce1/preview-7-light.png) | [dark](preliminary-870fc0ce1/preview-7-dark.png) | Composer specification; no supplied mock; review pending |
| Composer queue - Mid-turn delivery | [light](preliminary-870fc0ce1/preview-8-light.png) | [dark](preliminary-870fc0ce1/preview-8-dark.png) | Composer specification; no supplied mock; review pending |
| Composer queue - No mid-turn delivery, long message and files only | [light](preliminary-870fc0ce1/preview-9-light.png) | [dark](preliminary-870fc0ce1/preview-9-dark.png) | Composer specification; no supplied mock; review pending |
| DSMessageInput - Empty and multiline | [light](preliminary-870fc0ce1/preview-10-light.png) | [dark](preliminary-870fc0ce1/preview-10-dark.png) | Composer specification; no supplied mock; review pending |
| Composer agent menu - All agents and inline effort | [light](preliminary-870fc0ce1/preview-11-light.png) | [dark](preliminary-870fc0ce1/preview-11-dark.png) | Composer specification; no supplied mock; review pending |
| Composer mode menu - Four modes | [light](preliminary-870fc0ce1/preview-12-light.png) | [dark](preliminary-870fc0ce1/preview-12-dark.png) | Composer specification; no supplied mock; review pending |
| Composer where menu - Folder or new branch | [light](preliminary-870fc0ce1/preview-13-light.png) | [dark](preliminary-870fc0ce1/preview-13-dark.png) | Composer specification; no supplied mock; review pending |
| Quick Entry - Selection | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Quick Entry - Empty | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Quick Entry - First launch | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Quick Entry - Missing folder | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Quick Entry - Unavailable device | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Quick Entry - Narrow and long text | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next start - Rest, typed and failure | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Ask composer | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Starting task - Waiting for restart | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Starting task - Restart failed | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Letter | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Empty | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - First launch | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Offline | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Held | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Devices | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Attachments | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Changed defaults | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Two agents | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Failure | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Narrow | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Start fold | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - First message | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Compose - Settled | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next question - Choices | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next question - Free text | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next question - Several questions | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next question - Answer delivery fails | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next question - Narrow | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Question | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Plan | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Narrow plan | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Failure | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Plan without steps | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Previous plan | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Destructive hold | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Unknown command | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Plan delivery failure | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Next ask - Delivery failure | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Routine approval | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Destructive approval | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Question | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Question, narrow | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Confirmation question | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Answer delivery failed | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Failure | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Recovering | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Plan | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Finished | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Resolved | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Loading | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Missing task | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Peek - Long command, narrow | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Subagent inspector - Well question | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Subagent inspector | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Composer pending - Review draft comments | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Composer - queued edit before and after start | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Composer - Field rest, typing, loading and unavailable | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Composer - Field narrow | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Attachments section | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |
| Attachment chips | Pending on build Mac | Pending on build Mac | Composer specification; no supplied mock; review pending |

The narrow field retains the existing abbreviated agent label. Design review should assess this at the target widths.

Reproduction uses `scripts/dev/render-previews.py` with the actual preview bodies and app Debug module. `current-fixtures.swift` and `main-field-baseline.swift` preserve the prepared inputs. The former renders auto-focused Quick Entry, new-task and task-peek fixtures one appearance per window to avoid competing focus in the paired wrapper. These fixture wrappers use the real views and inert fixture models.

Queued row click-to-edit, drag reordering, accessibility actions and the context menu were restored at `224b37019`. Their live interaction and menu-state visual check are pending on the build Mac.

| Additional changed state | Screenshot | Matching reference |
| --- | --- | --- |
| Queued row context menu and edit focus | Pending on build Mac | Previous composer actions; review pending |
