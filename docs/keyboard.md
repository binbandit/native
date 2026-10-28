# Keyboard

Native is fully usable from the keyboard. This table is the single source of truth: every shortcut
here exists, appears in its menu (so it's discoverable and listed in the Keyboard Shortcuts sheet),
and nothing outside this table claims a key.

A row with a **Command** id is a command in the registry (`docs/commands.md`): the menu bar, the
command palette and Settings ▸ Keyboard Shortcuts all read it, and the user can change or remove its
shortcut there. The keys here are the defaults. `DefaultShortcuts` (`Packages/NativeCommands`)
mirrors them, and its tests fail when the two disagree, so change a key here first, then there.
Rows without an id are keys a view answers itself; they can't be changed.

On Mac, double-clicking empty title bar or toolbar space follows Desktop & Dock's title bar action
(Zoom, Fill, Minimize or Do Nothing). Zoom and Fill restore the previous window size on the next
double-click. Toolbar buttons, the task title and the well keep their own interactions.

Standard macOS behavior comes for free and must not be broken: Tab / Shift-Tab move focus through
controls (with Full Keyboard Access on), arrow keys move within lists and menus, Space activates the
focused control, Escape dismisses popovers and sheets, ⌘W closes the frontmost window or sheet, ⌘Q quits, ⌘, opens
Settings in the main window (and closes it again). In every sheet and dialog, Return activates the default (highlighted) button and Escape
cancels, so those keys don't get rows of their own.

File ▸ Close (⌘W) acts on the frontmost Native window or panel, including image previews and About.
A sheet closes before its parent window. Closing the last window leaves Native running; it never
quits the app or closes the main window behind another window. Settings and the task's terminal
panel live in the main window, so ⌘W there closes that window. Use Close Terminal Tab to end a
terminal tab instead. ⌘, brings the main window back with Settings; ⌘Q quits the app.

## Sending

| Keys | While the agent is idle | While the agent is working | Command |
| --- | --- | --- | --- |
| Return | Send | The preferred follow-up behavior (Settings: Steer, the default, or Queue) | |
| ⌘Return | Send | The other follow-up behavior | |
| Shift-Return, Option-Return | New line | New line | |
| Escape | Close the slash-command list if open | Stop the turn (with the slash-command list closed); again, end the cancel grace period | |
| ⌘. | | Stop the turn; again, end the cancel grace period | `session.stop` |
| ↑ in an empty composer | Edit the last queued message, if any; else recall the last prompt | Edit the last queued message | |

**Steer** adds the message to the running turn (`_session/steering`); agents that don't support
steering queue it instead. **Queue** holds the message above the composer
and sends it when the turn ends; queued messages go out one per turn, in order. A stopped or failed
turn holds the queue until you send again.

While the agent works, the composer keeps a plain message prompt. The send button's tooltip and
VoiceOver label describe whether it steers or queues, including the fallback for agents without
steering. Pending questions, approvals, stopping and unavailable tasks still explain what is
needed in the placeholder. Code-block and queued-message editing hints remain visible when the
controls row has room.

**Stop** asks the agent to end the turn and answers its open permission requests as rejected. The
button shows that it is stopping. After three seconds, or immediately on a second press, the host
freezes and ends the agent's known process tree, including shell commands in separate process groups.
The transcript marks unfinished tool calls Stopped. If the agent did not answer, the receipt says
"Stopped. <agent> didn't respond, so Native stopped it."

Native restarts the adapter and reattaches the conversation, retaining the transcript, draft and
paused queue. Other running tasks that shared the adapter recover through the same path as an agent
crash. Queued messages remain paused unless the user explicitly chose Send Now.

### Code

Fenced code blocks (a line of three or more backticks or tildes) and inline `` `code` `` show in the
composer in the code font (a block's fence lines dimmed, an inline span on a quiet fill); the text itself stays
exactly as typed or pasted, indentation, tabs and trailing spaces included. While the caret is in a
fenced block, from the moment its opening fence is typed until past its closing fence, Return and
Tab edit the code and the hint says "↩ New line · ⌘↩ Send":

| Keys (caret in a fenced block) | Action |
| --- | --- |
| Return | New line, indented like the line the caret is on |
| ⌘Return | What Return does elsewhere: send, the preferred follow-up while the agent works, or save a queued message's edit |
| Tab / Shift-Tab | Indent / outdent the caret's line or every selected line, by the block's own indent (a tab, or its spaces) |

`@` inside code is the code's own, so it doesn't open the file list.

### Queued messages

Each queued message has Send Now, Edit and Remove on hover; its menu (a right-click, or touch and
hold on iPad) adds Move Up and Move Down. Send Now steers the message into the running turn when the
agent can steer; otherwise it stops the turn and sends the message next. Drag a message to reorder
the queue. Clicking a message, or ↑ in an empty composer, opens it in the editor:

| Keys (queued message open in the editor) | Action |
| --- | --- |
| Return | Save the edit; the message keeps its place |
| ⌘Return | Save the edit and Send Now |
| ⌥⌘↑ / ⌥⌘↓ | Move it up / down the queue (Task ▸ Move Queued Message Up / Down) |
| Escape | Close it without saving |

If the message starts or is removed while you edit it, queued-edit hints and shortcuts clear
immediately. Your draft stays in the composer as a new message, including any unsaved edits.

## Agent questions

When an agent asks structured questions (Claude Code's AskUserQuestion, ACP form elicitation), they
dock above the composer as a card: the question, a `1/3` pager, options, a free-text row, and Skip /
Next. The card takes focus when it appears and the composer is empty. Plain digits pick options
only while the card has focus; ⌘1 – ⌘9 stay task navigation.

| Keys (card focused) | Action |
| --- | --- |
| 1 – 9 | Pick that option (toggle it, for questions that take several) |
| ↑ / ↓ | Move between options |
| Space | Pick the highlighted option |
| Return | Next question, or send the answers after the last |
| Tab / Shift-Tab | Move between the card, its free-text field and the composer |

With Fine print (`NativeComposerNext`) enabled, the question takes the composer's place, in the
approval's frame: "Claude Code asks", a `1 of 2` pager, choices on digit keycaps (a choice the agent
recommends is tagged and starts picked, so Return accepts it), Skip and Send for a single question,
or Next / Send Answers for several (Return). The composer's field below becomes "Or answer in your
own words"; Return there answers the shown question with what you typed. The draft waits
underneath until the questions are answered, and ⌘L focuses the answer field. Peek and Home show
the same question with the same keys; on Home, Open Task (⌘↩) sits at the field's trailing edge.
Long prompts and choices scroll inside the card. The pager, Skip / Next and answer field stay
visible; digit and arrow keys reveal the choice they select or highlight.

### A task that couldn't start (Fine print)

With Fine print enabled, a task whose agent couldn't start shows why in the composer's place,
above its message. When the agent's report names a file and line, the card shows that line with
the part it couldn't read underlined, and, when one value it accepts is close to the one it
rejected, a fix-it that changes it (keeping the original as `<file>.native-backup`). Undo on the
toast that follows, or ⌘Z while it's the latest change, puts the original back.

| Keys | Action |
| --- | --- |
| ⌘R | The card's main action: Fix and Retry (or Fix and Restart), Retry, Sign In, or Start in Project Folder |
| ⌥⌘O | Show or hide what the agent reported |

## Command palette

⌘K opens the palette over the window: every command that can run right now, plus the tasks in the
sidebar, the projects and the Settings pages, recently used ones first. With a terminal focused,
⌘K stays the terminal's Clear and the palette is a View menu item away.

| Keys (palette open) | Action |
| --- | --- |
| Type | Narrow the list; letters in order match too (`nwta` finds New Task) |
| ↑ / ↓ | Move the selection |
| Return | Run the selected command, or open the task, project or page |
| Escape | Close the palette |

## Commit popover

| Keys | Action |
| --- | --- |
| ⌘Return | Commit the selected files |
| Escape | Close the popover |

## MCP sign-in sheet

Return starts sign-in, submits a pasted redirect address while waiting, or closes a successful sign-in.
Escape cancels the pending sign-in and closes the sheet. Tab reaches Open Browser and the redirect
field; Space activates Open Browser. Closing the sheet stops its pending command on the host.

## Git sheets

| Keys | Action |
| --- | --- |
| ⌘Return in Smart Commit | Commit the planned groups |
| ⌘Return in the setup-script editor | Save the script new worktrees run (Settings ▸ Scripts) |
| ⌘Return in Clean Up Merged | Clean up the included items |

## Pull request page

| Keys | Action |
| --- | --- |
| ⌘Return in a comment box | Send it: comment, reply, add to the review, or save an edit |
| Escape in a new line comment | Discard it |
| Escape in a pull request row's comment box | Close it, keeping the text for next time |
| Click a line number | Comment on that line |
| Drag across line numbers | Comment on the lines dragged over, within one hunk and one side (on iPad: touch and hold a line number, then drag) |
| Shift-click a line number | Widen the line comment to a range (on iPad: "Extend Comment to Here" in the line's menu) |
| Return in the review sheet | Submit the review (merging always takes a click) |
| Escape in the review or merge sheet | Close it without submitting |
| ⌥⌘A | Show or hide Ask, the private question panel beside the page ("Ask" in the header) |
| Return in Ask's composer | Ask; while an answer is coming, queue the question for after it |
| Shift-Return, Option-Return in Ask's composer | New line |
| Escape in Ask's composer | Stop the answer |

## Slash commands

The list has Native's own commands first, then the agent's. Native runs its own rather than
sending them; an agent's command of the same name stays listed, and picking it from the list sends
it to the agent.

| Slash command | What Native does |
| --- | --- |
| `/clear` | Starts a fresh conversation in the same task, using the same agent, in the same folder, with the same settings and title. The earlier conversation stays with the agent, a click away: Earlier Conversation in the toolbar, or Task ▸ Open Earlier Conversation. It opens read-only, with Current Conversation (or Task ▸ Open Current Conversation) where the composer was. Task ▸ Clear Conversation and the palette do the same as `/clear` |
| `/goal …` | Sets, pauses, resumes or clears the task's goal |

| Keys | Action |
| --- | --- |
| / at the start of the composer | Open the command list |
| ↑ / ↓ | Move the selection |
| Return or Tab | Insert the selected command, then a space, with the caret after it |
| Escape | Close the list |

## File mentions

Typing `@` at the start of a word lists the project's files and folders (ignored files left out;
changed and recently mentioned ones first, a folder ahead of the files in it when its name matches),
narrowing as you type. A folder shows with a folder icon and a trailing `/`. The choice goes into
the draft as `@path` (`@src/components/` for a folder) and reaches the agent as a link to the file
or folder. Pasted or dictated `@` text opens the list the same way ([accessibility.md](accessibility.md)).

`@./` lists the project root's immediate folders and files, folders first. Continue with a partial
name to filter, or a folder path such as `@docs/` to browse there. Hidden paths are included when
they are in the project's file index; ignored paths stay out. `..` cannot browse outside the project.
Paths with spaces use straight quotes (`@"My Docs/"`); folder completion leaves the caret inside
the closing quote so the next characters continue the child name.

| Keys | Action |
| --- | --- |
| @ | Open the file list |
| ↑ / ↓ | Move the selection |
| Return or Tab | Insert the selected file and a space; for a folder, leave the caret after its `/` to continue the path |
| Escape | Close the list |

## Attachments

Files and images go out with the message as chips above the text: picked with the "+" chip or
⌘U, pasted, or dropped on the composer or the transcript. Images go to agents that take them
(scaled to fit 2048 pixels); small text files are embedded for agents that take embedded context;
anything else goes as its path. A picture that will reach the agent as a path (the agent takes no
images, or it's over 50 MB) says so on its chip before anything is sent. A message carries up to 20
files; a file moved or deleted before sending is marked on its chip and holds the message.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘U | Attach files | File | `composer.attachFiles` |
| ⌘V | Paste copied files or an image as attachments (text pastes as text) | | |
| Space or Return on a chip | Open it in Quick Look | | |
| ← at the start of the draft | Select the last file; ← and → move between files, → past the last returns to the text | | |
| Delete or ⌦ on a selected file | Remove it; Delete selects the file before, ⌦ the one after | | |
| Escape, or typing, with a file selected | Return to the text | | |
| Delete in an empty draft | Remove the last file (a held key doesn't) | | |
| Delete on a focused chip | Remove it from the message (with Keyboard Navigation on) | | |
| ⌘Z | Put back a removed file | Edit | |

## Permission requests

With the All in view sidebar experiment, ⌘Y targets the oldest connected task ask across all
projects, including child tasks. Its row carries the keycap. Routine approvals offering Allow once
are answered in place; questions, plans and commands with irreversible or unknown effects open
Peek for review. The full request is always shown there. The current task and its draft stay put.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘Y | Answer oldest task ask, or open its Peek | Task | `task.answerOldestAsk` |
| | Peek at the selected task (Space with the sidebar list focused) | Task / row context menu | `task.peek` |
| Escape in Peek | Close Peek | | |
| Return in Peek (except a question) | Open Task | | |
| ⌘R in a failure Peek | Retry the failed task | | |

A click on a row's signal, a force click, or Peek in its context menu opens the same 600pt Peek,
drawn in the window beside its row and never over the toolbar. Escape returns focus to the list
when it opened Peek; clicking outside closes Peek and keeps focus with the clicked control.
Questions keep their digit, arrow and Return controls. An answer closes Peek. Hidden or filtered
rows open it at the top of the content. The experiment defaults to off; the shortcuts below keep today's
behavior while it is off. Workflow and expedition approvals retain their local shortcut when no
task ask owns ⌘Y and the user has not reassigned it to another command.

The oldest pending request in the visible task answers these: a tool's permission request, a
workflow step waiting for approval, or an expedition's route (or route change) waiting for review.
They're chosen not to collide with text editing in the composer.

| Keys | Action |
| --- | --- |
| ⌘Y | Allow once (approve the workflow step) |
| ⌥⌘Y | Allow always (when offered, never for an irreversible action) |
| ⌘⇧⌫ | Reject |
| ⌘⇧Y | Ask the agent to use the suggested command (Fine print fix-it, when offered) |

With Fine print enabled, irreversible commands require a 0.6-second hold. Hold ⌘Y when the local
Allow once shortcut is available; All in view reserves ⌘Y for the oldest task ask. Releasing
before the hold fills sends nothing. Pointer and touch use the same hold; VoiceOver and Switch Control
use Allow followed by Confirm Allow within five seconds. The button acknowledges Allowed for
0.4 seconds before the request folds away. Reduce Motion keeps the ring but removes the fill sweep.
⌘L focuses Tell the agent what to do instead while an approval is shown; Return sends the instruction.
In Peek, this focuses the shown approval, including a child task ask or a Peek opened from Home,
without selecting its task or changing the current draft. Closing Peek restores Focus Composer.
The fix-it and every permission option are also in the keyboard tab order.
Only the oldest request owns these keys; changing tasks or losing the window cancels a hold.
When an agent offers several choices of one permission kind, each stays visible under its own name;
only the first owns that kind's shortcut. The iPad hold route is installed at the window root so
focus can remain in the sidebar, toolbar or transcript.

On an expedition's route review, ⌘Return approves too, and ⌘L focuses the message field for the
expedition's lead (the composer key, on a page without a composer).

## Transcript

Tool rows, exploration groups and condensed runs of tool calls start closed. Each is a button, so
it opens with a click, a tap, or from the keyboard. The task remembers opened and closed rows,
groups, runs and earlier turns while the app runs, including after switching tasks or transcript
styles. A run's header still counts running and failed calls while closed. Pending approvals stay
visible outside the groups; a container that holds one stays open until it is answered, then returns
to the user's choice.

| Keys | Action |
| --- | --- |
| Space on a focused tool row (Tab moves focus, with Keyboard Navigation on) | Show or hide its output |
| Space on a focused run of tool calls | Show or hide the run's list |

## Images and artifacts

Click or tap a transcript image or file to open its viewer. Tab then Space opens the focused
thumbnail or file chip. The viewer opens fitted to its available space and keeps the transcript's
place when closed. Pinch or double-click an image to zoom; drag to pan a zoomed image.

| Keys (viewer open) | Action |
| --- | --- |
| ⌘+ / ⌘= / ⌘− | Zoom in / out |
| ⌘0 | Fit the image to the viewer |
| Arrow keys | Pan a zoomed image |
| ⌘C | Copy the image or artifact |
| ⇧⌘S | Save As… |
| ⌘R | Show in Finder (a file on this Mac) |
| Escape | Close the viewer |

Other file types use the platform's Quick Look preview, with its native navigation and zoom.

## Tasks and navigation

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘K | Command palette: run any command, or jump to a task, project or Settings page | View | `palette.show` |
| ⌘/ | Keyboard shortcuts (also the "?" at the status bar's trailing end) | Help | `help.keyboardShortcuts` |
| ⌘N | New task with the last-used agent; with Compose Task on, open Quick Entry over the current task; on Home Next, focus its start field | File | `session.new` |
| ⇧⌘N | With Compose Task on, expand Quick Entry into New Task, keeping the draft and context | File | `task.compose` |
| ⌥⌘O | With Quick Entry open, choose the device the task runs on | File | `task.chooseDevice` |
| ⌥⌘N | New task with… (agent picker) | File | `session.newWithAgent` |
| ⌥⌘E | New expedition (`docs/expeditions.md`) | File | `expedition.new` |
| | Continue a task without a project in a chosen folder; optionally copy its private files | Task | `session.moveToProject` |
| ⌘O | Open folder | File | `project.open` |
| | The current project's settings (Settings ▸ Projects; also in the project's menu in the sidebar) | File | `project.settings` |
| | Refresh git and pull-request state for every task in the current project (also Refresh in its sidebar menu) | File | `project.refresh` |
| | Clean up the current project's merged task worktrees, branches and stale worktree records, after a review (also "Clean Up Merged…" in the project's menu in the sidebar) | File | `git.cleanUpMerged` |
| ⇧⌘O | Open the task's folder in the default app (Open In) | Task | `session.openInDefaultApp` |
| ⌥⌘P | Open the task's pull request, where clicking one goes (Settings ▸ GitHub); listed while its branch has one | Task | `pullRequest.openForTask` |
| ⌘L | Quote selected transcript or diff lines and focus the composer (Fine print); otherwise focus the composer | Task | `composer.focus` |
| ⌘[ / ⌘] | Back / forward through the tasks you've viewed | Go | `go.back` / `go.forward` |
| ⌘1 – ⌘9 | Go to the Nth task in the sidebar | Task | `session.select1` – `session.select9` |
| ⌃Tab / ⌃⇧Tab | Next / previous task | Task | `session.next` / `session.previous` |
| Return on a selected sidebar task | Rename it (Escape cancels, Return commits) | Task | |
| ⌃⌘S | Show or hide the sidebar | View | `view.toggleSidebar` |
| | With All in view on and the sidebar hidden, show tasks needing you (also the amber toolbar count) | Task | `task.showNeedsYou` |
| ⌥⌘↑ / ⌥⌘↓ | Move the selected project or task up / down (a queued message instead, while one is open in the composer) | Task | `sidebar.moveUp` / `sidebar.moveDown` |
| ⌘Z / ⇧⌘Z | Undo / redo the window's latest change, newest first: typing, or archiving, renaming, pinning or deleting a task or project (a deletion until it's carried out). The undo toast's Undo takes back the same change, once | Edit | |
| ⌘Z after removing a host | Restore the removed host's pairing, also offered by the toast's Undo | Edit | |
| ⇧⌘A | Archive the selected task and open the next task in the sidebar's current filter and sort order (or the previous task at the end). ⌘Z or the toast's Undo restores and reopens it. Unarchive an archived task; with several tasks picked, archive them all | Task | `session.archive` |
| ⌥⌘J | Turn the sidebar's Needs you filter on or off (its filter menu has the rest) | View | `view.needsYouFilter` |
| ⌘⇧P | Pull requests | Go | `go.pullRequests` |
| | GitHub Account: open Settings > General at Accounts (Mac only) | Go | `github.accounts` |
| Tab, then Space on the sidebar footer | Open Settings > General; account controls live in Accounts | | |
| ⌘⇧X | Expeditions | Go | `go.expeditions` |
| ⇧⌘F | Search every task (`docs/search.md`) | Go | `search.show` |
| ⌥⌘I | Show or hide the subagent inspector | View | `view.toggleSubagentInspector` |
| ⌘⇧D | Show or hide the changes inspector (the task's uncommitted git changes) | View | `view.toggleChanges` |
| ⌃⌘M | Show the task's MCP servers (the server chip beside the composer's context ring; with Fine print, the MCP servers page in Task Settings) | View | `view.mcpServers` |
| | Show what fills the task's context window, even while Fine print's field hides its ring (under 70% full) | View | `view.contextUse` |
| ⌃⌘A | Keep Mac awake: cycle Off → While agents work → On (View ▸ Keep Mac Awake) | View | `keepAwake.nextMode` |
| | Show or hide the status bar along the window's bottom edge (on by default) | View | `statusBar.toggle` |

Undo toasts show ⌘Z only while the window's next Undo takes back that offer. Tab reaches Undo and
the corner Dismiss button; VoiceOver exposes both as actions on the announced message. Hover or
keyboard focus holds the toast open. Escape keeps its task behavior and never dismisses a toast.
On iPad, the corner Dismiss button is always visible and swiping down dismisses the toast.

## Home Next (Labs)

With Next enabled in Settings > Labs, Home shows one ask at a time. The visible approval owns
the usual permission keys: Cmd-Y allows once, Option-Cmd-Y always allows when offered, and
Shift-Cmd-Delete rejects. Tab and Space reach Up next, Open Task, the ordering menu, and Show
more. Tab / Shift-Tab leave the instruction and answer fields without inserting a tab.
Up next opens Peek; its Open Task action enters the conversation. Cmd-Return opens the
current ask's task; Shift-Cmd-Down shows the next five rows.
Cmd-N focuses the start field at the bottom of Home; Cmd-O opens a folder, including before the
first project exists. The start field writes Quick Entry's draft to Quick Entry's address: Return
starts the task and stays on Home, Cmd-Return starts it and opens it, Shift-Return and
Option-Return insert a new line, and Escape leaves the field. Shift-Cmd-N (with Compose Task on)
moves the draft onto the New Task page.
The current question uses the composer's question keys: 1-9 pick an offered choice, Return
sends, and typing in the answer field keeps digits as text. Plans use Cmd-Y to approve,
Shift-Cmd-Delete to request a revised plan.
Option-Cmd-Down shows the full plan in Peek without leaving Home. Cmd-L focuses the current
approval's instruction field, or with Fine print the question's answer field. Escape dismisses Peek. A failed task uses Cmd-R to retry and
Option-Cmd-O to show its error output. Cmd-Return opens the task for every ask kind.

## Task tools (Labs)

With The well enabled (`NativeTaskWell`, off by default), Cmd-I opens the centered task well.
Its tools appear in this fixed key order. Missing tools leave no row; their keys stay reserved.
Clicking a waiting well focuses the composer, where the full request can be answered.
Dev reveals the latest project action in the workbench, or its action chooser before the first run.
Up and Down move through the tool list and Return or Space opens the highlighted tool, as in a
menu. Subagents opens a roster; Return or Space on a row opens that worker. Escape returns from a
chooser to the tool list, then closes the well. Terminal and Dev keep their existing run, stop,
new-tab and hide commands in the workbench under the composer. A tool turned off in Settings ▸
Task Tools has no row and its key does nothing. Task ▸ Rename Task… (no default keys) opens the
title's popover for the task in view: Return keeps the name, Escape puts it back. Where GitHub is
out of reach, Task ▸ Export Patch… (no default keys) stands in for the pull request.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘I | Open or close the task well | View | `taskWell.toggle` |
| ⌥⌘1 | Changes | View ▸ Tools | `sessionTools.changes` |
| ⌥⌘2 | Terminal | View ▸ Tools | `taskWell.terminal` |
| ⌥⌘3 | Dev (project actions) | View ▸ Tools | `taskWell.dev` |
| ⌥⌘4 | Subagents | View ▸ Tools | `taskWell.subagents` |
| ⌥⌘5 | Pull request | View ▸ Tools | `taskWell.pullRequest` |
| | Export the branch as a patch, where GitHub is out of reach | Task | `taskWell.exportPatch` |
| Escape | Close the well and return focus to the task | | |

With The well enabled, narrow Changes replaces the conversation and keeps the composer below.
Escape, or the esc key in its header, returns to the conversation. The file pop-up also chooses
This Turn, Uncommitted or Branch. Its diff quotes selected lines the same way as every other diff.

With Task Tools enabled in Settings ▸ Labs (off by default), the Changes fact under the title
opens the changes panel. It docks beside a wide conversation and overlays a narrow one.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌥⌘1 | Show or hide Changes (same command as above) | View ▸ Tools | |
| ⇧⌘D | Show or hide Changes, as on the standard task screen | View | |
| Escape | Close the Changes overlay before composer Stop, suggestions or attachment actions; while focus is in the docked panel, close that panel | | |

## Quitting

With "Keep agents running when Native quits" on (Settings ▸ Background, the default), ⌘Q quits only
the app: agents keep working in Native's background host, and the next launch shows what they did
while you were away (`docs/durability.md`). The command below stops them too. It's listed while
agents would outlive the app; otherwise ⌘Q already stops them. The extra modifier keeps it from
being hit by accident, since it ends work in progress.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌃⌥⌘Q | Quit Native and stop its agents: ends known commands, reports unverified stops, and exits the background host until Native opens again | Native | `app.quitAndStopAgents` |
| | Restart Background Host…: confirms before restarting this Mac's host; offers to wait for busy tasks or interrupt and resume them | Native | `app.restartBackgroundHost` |

Restart Background Host… is also in Settings > Background. Cancel leaves the host alone. With tasks
running or waiting, Return chooses Wait Until They Finish; Escape cancels. The action is unavailable
while restarting or this Mac has no background host. While waiting, the row names the blocking tasks
and Restart Now… opens the same confirmation. Escape preserves the scheduled restart. It never restarts
a paired host.

## Opening folders (All in view)

File > Open Folder… (⌘O, `project.open`) opens the system folder-only chooser directly,
including before the first project and with the sidebar hidden. The plus in the Projects
header does the same, stays visible on touch, and is reachable with Tab. Return or Space
opens the chooser. Compose, Home's start field and Quick Entry end their project pickers with
Open Folder…. The no-project Home keeps one primary Open Folder… action. File > Open Recent
lists up to six successfully opened folders on this device. Tab also reaches the single
Settings button in the footer; Return or Space opens Settings.

Drop one or several folders anywhere on the sidebar to add them without starting a task.
The persistent addition receipt offers Undo; ⌘Z undoes that addition when it is the applicable
window action. Text editing keeps its normal undo precedence. Choosing an already open folder
focuses its home without adding another project or another undo action.

## Picking tasks in the sidebar

With All in view on, View > Sidebar and the list context menu offer task ages, finished-task
changes, agent names, branches, machines and ask text. Fold Tasks Older Than chooses A Day
(the default), A Week or Never. The "earlier" disclosure is keyboard focusable; Space toggles
it. Filters show every matching task. Arrow navigation, Next/Previous Task, numbered task shortcuts and bulk selection exclude folded earlier tasks;
search and history reveal a selected older task. Home Next owns the full ask it is showing,
so the matching sidebar row keeps its title and signal.

With All in view on, hiding the sidebar keeps back and forward in the toolbar. While tasks need
you, one amber signal counts them. Click it or choose Task > Tasks Needing You to open the list.
Up and Down highlight a task; Space, Return or a click opens its shared Peek without changing the
current task or draft. Escape returns from Peek to the list, then closes the list. Answering the
last ask removes the signal; unresolved failures also count until they recover.

Several tasks can be picked at once and acted on together. While more than one is picked (or Select
Tasks is on, which makes taps pick, for touch), a bar at the foot of the sidebar says how many, with
Archive, Mark as Read, Delete and the rest under More; a picked task's context menu offers the same.
Each action applies to the picked tasks it would change. Archiving, pinning and deleting offer one
Undo for all affected tasks. Delete hides them immediately and waits 10 seconds before cleanup, so
Undo keeps every task untouched.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘-click a sidebar task | Pick it, or let it go; the first ⌘-click picks the open task too | | |
| ⇧-click a sidebar task | Pick every task from the last one picked (or the open task) to it | | |
| ⌘A with the sidebar focused | Pick every task in the open task's project (in Pinned, every pinned task) | | |
| Escape with tasks picked | Let them go | | |
| | Select Tasks: taps pick instead of opening (also in the filter popover on iPad) | Task ▸ Selected Tasks | `sidebar.selectMode` |
| | Pick every task in the project | Task ▸ Selected Tasks | `sidebar.selectAll` |
| | Let the picked tasks go | Task ▸ Selected Tasks | `selection.clear` |
| | Archive the picked tasks | Task ▸ Selected Tasks | `selection.archive` |
| | Unarchive the picked tasks | Task ▸ Selected Tasks | `selection.unarchive` |
| | Delete the picked tasks immediately; Undo for 10 seconds before cleanup starts | Task ▸ Selected Tasks | `selection.delete` |
| | Mark the picked tasks as read | Task ▸ Selected Tasks | `selection.markRead` |
| | Mark the picked tasks as unread | Task ▸ Selected Tasks | `selection.markUnread` |
| | Pin the picked tasks | Task ▸ Selected Tasks | `selection.pin` |
| | Unpin the picked tasks | Task ▸ Selected Tasks | `selection.unpin` |
| | Stop the turns running in the picked tasks | Task ▸ Selected Tasks | `selection.stop` |

## Task settings

Extra agent settings, such as Claude Code's Agent selector, always live in the composer's More
Controls ("…") menu. Each setting lists its choices with the current value checked; use the arrow
keys and Return to choose from the menu. Model, effort, autonomy and mode keep their dedicated
controls, moving into More only as the row runs out of room.

With Fine print (`NativeComposerNext`) enabled, the field's trailing controls are, left to right:
the context ring (only from 70% full), the Task Settings door (the agent and model, led by the mode when it
isn't Build), the paperclip (Attach Files, ⌘U) and Send or Stop. The door opens one Task Settings
popover: the model and its effort, when the agent asks, then the task's rows (Mode, Goal, MCP
servers, Web search when the agent offers it, and the agent's own settings). Choose Model (⌘⇧E)
opens it with the current model highlighted; a click opens it with nothing highlighted until a key
is pressed. Show MCP Servers (⌃⌘M) opens the MCP servers page in place, and goal commands open the
goal page in place, even when Task Settings is closed. A page's first line goes back to Task
Settings, as Escape does.

| Keys in Task Settings | Action |
| --- | --- |
| ↑ / ↓ | Every row, top to bottom, across sections; skips headers and locked rows. The caption under a list describes the highlighted row |
| ← / → | On Effort, change its level (applies at once). On Mode, Goal, MCP servers or the agent's own settings, → opens its page or its choices in place; ← comes back |
| Tab / ⇧Tab | Next / previous section: Agent, Model (including Fast mode), Effort, When it asks, the task's rows, and any retry action. A section lands on its current choice. In Compose, Tab follows native focus through agents, Add Agent and every settings control |
| Letters | Up to 8 models: jump to the row whose name starts with what's typed (as in menus). 9 or more: type into the model filter, which matches only the current agent's model names and values |
| Return | Choose and close. On a menu row, list its choices in place |
| Space | Choose and keep the popover open |
| Escape | Clear the filter; else leave a page; else close |
| ⌘Z | Undo the last change made in the popover |

When extra agent settings exhaust the height budget, the short model list ends with **N more models**.
Return or Space on that row opens the full Model page; Escape or the back row returns to Task Settings.
Lists past eight models keep the filter, with the last slot showing **N more match. Keep typing.**

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘⇧M | Next permission mode | Task | `session.nextPermissionMode` |
| ⌃⇧M | Next mode: Build, Plan, Ask, Debug, Review, then your own modes and the project's (the composer's Mode pill) | Task ▸ Mode | `session.nextMode` |
| | Put the task in a mode, one command per mode ("Debug Mode"); your own and the project's modes get theirs too | Task ▸ Mode | `mode.build` / `mode.plan` / `mode.ask` / `mode.debug` / `mode.review` |
| | Edit Modes… (Settings ▸ Modes) | Task ▸ Mode | `modes.edit` |
| ⌘⇧E | Model picker | Task | `session.chooseModel` |
| ⌃⌥⌘A | Switch Agent: open the picker on the current agent | Task ▸ Switch Agent | `session.changeAgent` |
| | Change Workspace…: choose a branch, new worktree or project folder before the first message | Task | `session.changeWorkspace` |
| ⌥⌘G | Set or edit the task's goal | Task | `goal.edit` |
| ⌥⌘R | Run a workflow | Task | `workflow.run` |

## Choosing an agent

With Change Agent enabled in Settings > Labs, the composer's model control names both the
agent and model ("Claude Code · Haiku 5.5"). Its first section is Agent: installed agents in a
compact row, with the current one checked. The models below belong only to the current agent.
This works with Fine print on or off. Task ▸ Switch Agent lists the same agents; Choose Agent…
(⌃⌥⌘A, `session.changeAgent`) opens the picker on its Agent section. The command palette finds
"Switch Agent". Return chooses and closes; Space chooses and keeps the picker open.
Selecting another agent prepares its default model immediately without sending a message.
Context goes with the next message you explicitly send. The task keeps its folder, branch,
draft, attachments and quoted sources. Earlier conversations stay accessible. While a normal
turn runs, the choice waits for it to finish. Answer pending requests and send or remove queued
messages first. Goals that cannot move safely must be cleared.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| | Cancel a waiting or preparing model choice | Task | `session.cancelModelChange` |
| | Undo the latest reversible model choice, including after dismissing its receipt | Task | `session.undoModelChange` |
| ⌘Z | Undo the choice in normal window undo order; text edits keep precedence | Edit | |

The persistent receipt above the field and the transcript divider offer Undo before the next
message. After submission, Continue with the earlier agent makes a new choice; it cannot unsend
a message. Escape dismisses the list without cancelling preparation. No title-bar agent button
or review sheet is part of this path in either composer.

New Task With… (⌥⌘N) opens the agent picker in a sheet: every agent Native runs, each with
its state (ready, starting, needs sign-in, not installed, stopped) and, when it can't start a
task, why and what to do, with the fix (Check Again, Restart) beside it. It opens with the
keyboard in its filter and the default agent (the one ⌘N starts) highlighted. Add Agent… at the
end lists the agents Native knows but can't find. Close dismisses the picker with pointer or touch.

When every installed agent has failed to start, New Task (⌘N) opens this recovery picker too.
It names the failed agents and offers Restart beside each one, plus Agents Settings. Home shows
the same failure with Restart on its agent cards and a link to Settings > Agents.

| Keys (picker open) | Action |
| --- | --- |
| Type | Narrow the list by name; letters in order match too |
| ↑ / ↓, ⌃N / ⌃P | Move between the agents that can start a task (and Add Agent…) |
| Return | Start the task with the highlighted agent; one that needs sign-in signs in first, then starts it |
| Escape | Clear the filter; with it empty, close the picker |

## Quick Entry (Compose Task experiment)

With `NativeComposeTask` on (off by default), ⌘N opens Quick Entry 12pt below the toolbar.
The current text selection in Native is included as removable context. The address reads
"to [agent and model] on [device] from [project]", in that order.

| Keys (Quick Entry open) | Action |
| --- | --- |
| Return | Start the task and stay on the current task |
| ⌘Return | Start the task and open it |
| Shift-Return, Option-Return | Insert a new line |
| ⇧⌘N | Expand into New Task, keeping the draft and context |
| ⌥⌘O | Open the device picker |
| Escape | Close the picker first, then Quick Entry; keep the draft for next time |

Expanding opens the Compose page without creating a task or worktree. The page keeps the draft,
quoted context and attachments. Return starts the task; Shift-Return and Option-Return insert a
new line. The toolbar's Start does the same. File > Attach Files (⌘U) attaches to the page;
Option-Command-O opens its device picker. Escape closes a picker before returning to writing.
Command-L focuses the page editor; Shift-Command-E opens its agent and model popover. Task-only
commands, such as goals and archiving, stay unavailable until Start creates the task.
An offline device offers Hold and Run on This Mac together; Return holds the task for that device.
Cancel Hold keeps the draft editable. Escape cancels a pending Start until its task has opened.
After a background start, the confirmation's Open button opens that task. Quick Entry
captures only a selection inside Native; global shortcuts and capture from other apps are not
part of this experiment.

### Two agents

The page's To line can name a second agent (the + after the first). Start then makes two tasks
from the one brief, each in its own worktree, grouped in the sidebar under the brief's title. When
both are at rest, the card at the end of either transcript compares them and keeps one. Keeping
one archives the other: its worktree goes, its branch and uncommitted work are saved as a
checkpoint, and Undo (the toast, or ⌘Z) brings it back as a group.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| | Show both versions side by side, file by file (also Compare on the card) | Task | `task.compareVersions` |
| | Keep the selected task's version and archive the other (also Keep on the card and in Compare) | Task | `task.keepVersion` |
| Escape in Compare | Back to the task | | |
| ⌘Z after keeping one | Bring the other task and its worktree back, and group them again | Edit | |

## Choosing a device

New Task's device picker says where the task runs: This Mac or a paired host (Settings ▸ Hosts),
each with whether it's online and has the project. It opens with the keyboard in its list; devices
that can't take the task stay listed, dimmed, with the reason.

| Keys (picker open) | Action |
| --- | --- |
| ↑ / ↓ | Move between the devices that can take the task |
| Return or Space | Choose the highlighted device |
| 1 – 9 | Choose the Nth device in the list |
| Escape | Close the picker |

## Settings

With Plainly settings enabled in Labs, the same navigation keys use the new page map. The command
palette lists its page names too. New Tasks contains the existing defaults and an Edit Modes
disclosure; Tab and Space reach these controls. Old page links open their new section (Scripts
in Git, for example). No shortcuts change.

| Keys | Action |
| --- | --- |
| ⇧⌘H in Hosts | Add Host: enter an SSH destination or paste a pairing link |
| Return in Add Host when the organization stops pairing | Close the sheet |
| ⇧⌘C in Add Host when the organization stops pairing | Copy the organization's help contact, when configured |
| ⌘F | Focus the search field |
| ↑ / ↓ | Move through the search results |
| Return | Open the highlighted result |
| Escape | Clear the search; with it empty, close Settings |
| ⌘[ | Return from a celebration detail page first; otherwise close Settings (Go menu) |
| ↑ / ↓ in the page list | Move to the previous / next page |

In Agents, Tab focuses each agent's Native tools switch and Space toggles MCP delivery for newly
opened tasks. Claude Code and Codex use the on-demand skill while that switch is off.

## Search

The search panel (⇧⌘F, Go ▸ Search Tasks…, or the magnifying glass in the window toolbar between
the sidebar toggle and the history arrows) keeps focus in its field, so typing always refines the
search. The toolbar button stays available with the sidebar collapsed.

| Keys (panel open) | Action |
| --- | --- |
| ↑ / ↓ | Move through tasks and their matches |
| Return | Open the selected task, scrolled to the selected match |
| Escape | Clear the search; with it empty, close the panel |

## Terminal

Each task has a terminal panel under the composer, opening in the task's folder (`docs/terminal.md`).

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌃` | Show the task's terminal and focus it; with the terminal focused, hide it and return to the composer | View | `terminal.toggle` |
| ⌃⇧` | New terminal tab | View | `terminal.newTab` |
| | Close the terminal tab (asks first when a program is running in it) | View | `terminal.closeTab` |
| | Retry the selected terminal command, including worktree commands | View | `terminal.retryJob` |
| | Stop the selected terminal command | View | `terminal.stopJob` |

While a terminal has focus, Native's menu shortcuts come first, then the terminal's own bindings,
then the shell. With "Use my Ghostty settings" on, the bindings are the user's Ghostty key
bindings (`docs/terminal.md`); otherwise they're these:

| Keys | Action |
| --- | --- |
| ⌘C / ⌘V / ⌘A | Copy the selection, paste, select all (Edit menu) |
| ⌘K | Clear the screen and scrollback |
| ⌘Home / ⌘End | Scroll to the top / bottom of the scrollback |
| ⌘PageUp / ⌘PageDown, ⇧PageUp / ⇧PageDown | Scroll by a page |
| ⌘⇧↑ / ⌘⇧↓ | Jump to the previous / next prompt |
| ⌘← / ⌘→, ⌘⌫ | Start / end of the line, delete to the start of the line (sent to the shell) |
| ⌥← / ⌥→ | Back / forward one word (sent to the shell) |

## Project actions

A project's actions (Test, Install, Dev…) run in the visible task's worktree, from the header's Run
button, the Run menu in the menu bar, the palette and the project's menu (`docs/actions.md`).

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⇧⌘R | Run the header's named action in the visible task (last run, or the first available action) | Run | `projectActions.runLast` |
| ⇧⌘. | Stop the visible task's running actions (⌃C; again to end them) | Run | `projectActions.stop` |
| | Edit the project's actions (its settings page) | Run | `projectActions.edit` |

Every action is also a command of its own, "Run: Test" (`projectActions.run.test`, named after the
action), listed in the Run menu and the palette while the visible task's project has it. None has a
default key; one given in Settings ▸ Keyboard Shortcuts runs that action in whichever project is in
view.

| Keys | Action |
| --- | --- |
| ⌘Return in the action editor | Save the action |

## Appearance

Light, dark or the system's, as in Settings ▸ Appearance (View ▸ Appearance). No default keys; give
them one in Settings ▸ Keyboard Shortcuts.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| | Follow the system's light or dark appearance | View | `appearance.system` |
| | Light | View | `appearance.light` |
| | Dark | View | `appearance.dark` |
| | Try on code themes on the task in view (from Settings or Home, the latest task with code; the sample task when there is no code to show) | View | `appearance.tryOn` |

Try On (Settings ▸ Appearance ▸ Try On…, or View ▸ Appearance ▸ Try On Themes…) turns the sidebar into
the theme list and recolors the window as the highlight moves. Focus starts in the list, on the theme
in use. Task controls are disabled while trying; agents keep running. It's unavailable while an
organization sets the code theme.

| Keys | Action |
| --- | --- |
| ↑ / ↓ | Highlight the previous or next theme, and show it |
| Home / End | Highlight the first or last theme |
| ← / → | List Dark mode's or Light mode's themes (the window shows that mode meanwhile) |
| Typing a name | Highlight the first theme it starts ("to" for Tokyo Night) |
| Return | Keep the highlighted themes and backgrounds, and go back |
| Escape, ⌘. | Cancel: write nothing and go back, from anywhere in the window. The task's turn keeps running: Stop (⌘.) steps aside until Try On ends |

## Ownership

Commands live with their features and register in `NativeApp` (`docs/commands.md`); the menus place
them. Composer keys in `native/Views/Composer*`; permission keys in
`native/Views/Transcript/ToolPermissionButtons.swift`; sidebar keys in `SidebarView`; Settings keys in
`SettingsScreen` and `SettingsSearchField`; search panel keys in `TranscriptSearchPanel`; agent picker keys in
`native/Views/AgentPicker/AgentPickerPanel.swift`; terminal commands in
`native/Terminal/Views/TerminalCommands.swift`; project action commands in
`native/ProjectActions/Commands/ProjectActionCommands.swift`; mode commands in
`native/Modes/Commands/ModeCommands.swift`; keys inside a terminal in
`GhosttyConfiguration.keybinds` (`Packages/Terminal`). Change a key here first, then in code.

## Celebrations

| Keys | Action | Command |
| --- | --- | --- |
| ⌥⇧⌘H | Restore the usual icon and Home while a celebration shows (skips it until it next occurs), or bring a skipped one back (View menu) | `celebration.restore` |

In Celebrations, Tab focuses a row, Space toggles it, and Return opens its detail page.
Escape or ⌘[ in a celebration detail page returns to the list at its previous scroll position
before closing Settings. The bulk-change confirmation also supports ⌘Z and Redo.

## Coordinator tasks (Labs)

With Settings > Labs > Coordinator tasks enabled, File > New Coordinator Task opens the assignment
picker in the current project. File > Edit Assigned Tasks edits the selected coordinator. Both
commands are also in the command palette. They have no default shortcut. Tab, Space and Return
operate the picker; Escape cancels without changing assignments.

## Command knowledge (Fine print in Labs)

These Help menu actions have no default shortcut and can be rebound in Settings > Keyboard Shortcuts.
They appear only while Fine print is enabled.

| Keys | Action | Command |
| --- | --- | --- |
| | Command Diagnostics (opens Settings > Privacy) | `help.commandDiagnostics` |
| | Count Unknown Programs Locally | `privacy.countUnknownPrograms` |
| | Clear Unknown Program Counts | `privacy.clearUnknownPrograms` |

With Fine print enabled, select transcript text and choose Task > Focus Composer (⌘L) to quote
its source lines. Quote in a transcript block's context menu quotes its selection, or the whole
block if nothing is selected. In a diff, select a line number, then another to extend the range, and choose
Quote Selected Lines or ⌘L. Two numbers on the same side quote only that file version;
selecting across old and new numbers includes both versions separately. Line buttons and Quote Selected Lines also work with Tab and Space
and touch. Remove Quote is beside each quoted source; ⌘Z restores a removed quote. Quotes are
snapshots of the selected text, including old/new line identity. File references in the draft and
@ list show the current known additions and removals; unknown counts stay absent.
