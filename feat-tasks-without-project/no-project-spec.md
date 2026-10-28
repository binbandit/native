# No project

Design source: no-project.html. Extends Compose + Quick Entry, Home Next and All in view. One resolved direction, dark and light for every state. Uses the approved window tokens and drawings from new-session.html, with Open Folder remaining fixed above the account as in requests-1026.html.

## Product contract

- No folder is required. No project means one Native-owned private scratch folder per task, never the home directory, current process directory or a shared temporary directory.
- The agent receives that real directory. This is a working location, not an OS sandbox or a promise that the agent cannot access anything else. Existing agent permission and managed network policy applies.
- The sidebar's No project group uses ordinary task rows, filters, search, pin, rename, archive and delete. It is not a project and has no project settings, repository or folder actions.
- Archive retains private files. Delete waits for the existing ten-second Undo grace period, closes the agent task, and then removes only Native-owned scratch files. Failed cleanup must be visible and retryable. An unconfirmed close keeps the task listed and its files intact, using Native’s existing action failure alert with the next step to open the task and retry deletion. Process snapshots do not authorize cleanup.
- Move to Project continues the conversation using the agent's history loading capability. An agent that cannot reopen a conversation explains the limitation. Never silently discard history or send a summary in place of the conversation.
- The move waits for a running turn to finish. Draft and attachments stay. A folder chooser is followed by a review sheet. Copy task files is an explicit opt-in, default off. Copies go into a unique Task Files subfolder; no existing project files are replaced. Originals remain until task deletion. On error the task remains in No project and the draft and originals survive.
- Scratch tasks run locally. A paired host requires an explicit project checkout; no invisible remote path is invented.

## States and tokens

| Mock | State | Native mapping |
| --- | --- | --- |
| n1 | Compose ready, No project | `.dsDisplay`, `DS.Tracking.display`, `DS.ComposeTask.width` 680, label width 40, gap 18, row 30, rule gap 14, editor gap 24. Letterhead is primary text, never a placeholder. Remove From row. Note `.dsBody` / `.dsTextTertiary`. |
| n2 | Home first task | Existing HomeNext start field and address. No project selected, send available when agent is available and message exists. Keep Open Folder optional. |
| n3 | Quick Entry | `DS.QuickEntry.width` 760, existing address picker, one No project option first. No branch suffix. Note uses `.dsCaption`, `.dsTextTertiary`. |
| n4 | Task and sidebar | `SessionRow` / `AllInViewTaskRow`, existing status language. Group uses existing sidebar project header rhythm but only New Task action. Subtitle No project. Git controls are absent in both default and Labs presentations. Title menu contains Move to Project… |
| n5 | Move review | Existing sheet pattern, `DS.TaskWorkspace` sheet width and spacing, `.dsTitle3` heading, `.dsBody` copy, `SettingsSwitch` or native accessible checkbox, `.ds(.primary)` Move and `.ds(.secondary)` Cancel. Folder name truncates in the middle with full accessible value. |
| n6 | Moving | Shared `DotGridLoader` and Moving… status beside unavailable Move controls; prevent duplicate move and send. No indeterminate empty sheet. |
| n7 | Moved | Catalog group and task subtitle become the chosen project; conversation, title, order, pin, draft and attachments survive. Inline notice confirms where it moved. Git becomes available only if the destination is a repository. |
| n8 | Failure | Error beside Move, `.dsAttention`; retained folder choice and copy preference; Retry through Move, Cancel back to the intact task. No data deletion on failure. |
| n9 | Delete / archive | Existing undo toast, keyboard undo, ordinary archived rows. Files are not cleaned during Undo grace or on archive. |
| n12 | Delete refused | Existing `ActionFailure` alert with native system chrome, title, agent reason and separate recovery paragraph. The row, draft and files remain. Return or Escape dismisses OK; VoiceOver reads the title, reason and next step. |
| n10 | Managed / offline | Existing agent restrictions and network admission, no new network calls. Disallowed agent unavailable with attributed policy reason. A permitted local agent can run offline. |

Palette: dark background #0D0D0E, sidebar #070708, surface #141416, overlay #18181B, text #E9E9E6 / #A5A5A8 / #85858A, separator #1F1F22. Light background #FBFBFB, sidebar #F0F0F0, surface/overlay #FFFFFF, text #181818 / #505050 / #8D8D8D, separator #E8E8E8. All app styling uses existing DS semantic tokens. Geist and Geist Mono from Native, no new assets. Glass only for toolbar and composer.

## Keyboard and VoiceOver

- Cmd-N: Quick Entry when Compose enabled, Home start focus on Home Next, otherwise start a task. All work with no focused project.
- Shift-Cmd-N: Compose page, retaining its address and draft.
- Cmd-O remains Open Folder. Choosing No project is a standard picker option reachable by arrows and Return.
- Task > Move to Project… is a discoverable menu command, no default shortcut. The task title menu and sidebar context menu expose the same model action.
- Move sheet: Tab through folder choice, copy option, Cancel and Move. Return moves only after a folder is selected; Escape cancels while idle. Moving exposes progress and keeps controls unavailable until settled.
- VoiceOver announces No project, task status and task title using existing row semantics. Move to Project has the same accessible name everywhere. Copy option says where files go, no path containing personal data is required. Failure is readable beside the action. Touch has the same menus and sheet; no hover-only entry point.
- Reduced motion retains static status and immediate state transitions. No new animation.

## Design director review

Keep the ordinary editor, row and task frame. No special scratch badge, new sidebar icon language, added toolbar action or empty From row. The folder choice stays where Compose already puts it. Move has one primary action and names the exact copy consequence before it happens. No project is a stable grouping, never an error state. Light and dark render as pairs for comparison.

## Direct New Task before the first message

Mock n11 covers the task created directly by the sidebar or the agent picker, with Compose off. It uses `EmptyStateView`, the existing `.dsCalloutMedium` / `.dsBody` hierarchy and primary Write a Message action. The action focuses the composer, as Cmd-L does. No repository suggestions, branch, worktree or private working path appear. Both the sidebar New Task button and New Task With agent command remain available with no project.

## Implementation review

The running app reuses the current shared composer, menus, task rows and undo toast. Inactive window chrome and macOS sheet corners follow the platform. The mock keeps the approved page geometry; current main also includes Workflows navigation and omits the signed-out account footer. Those shared changes are outside this feature.

The first visual pass caught a narrower Move sheet and small action buttons. The implementation now fixes the Mac sheet to the 520pt design token and uses medium shared buttons, while retaining flexible width on iPad. The first-launch page explicitly names Home in the toolbar.

Evidence: compare.html. Each state pairs app-nN-dark/light.png with mock-nN-dark/light.png. The final review remains with the coordinator.

Final direction refinements: moving uses the shared inline progress pattern, and recoverable move failure uses the attention token. The ordinary Delete flow returns to Home while its Undo toast is visible. Native sheet chrome and the existing Home, composer and toast geometry follow current main.
