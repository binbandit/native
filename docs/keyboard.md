# Keyboard

Native is fully usable from the keyboard. This table is the single source of truth: every shortcut
here exists, appears in its menu (so it's discoverable and listed in the Keyboard Shortcuts sheet),
and nothing outside this table claims a key.

A row with a **Command** id is a command in the registry (`docs/commands.md`): the menu bar, the
command palette and Settings ▸ Keyboard Shortcuts all read it, and the user can change or remove its
shortcut there. The keys here are the defaults. `DefaultShortcuts` (`Packages/NativeCommands`)
mirrors them, and its tests fail when the two disagree, so change a key here first, then there.
Rows without an id are keys a view answers itself; they can't be changed.

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
host gives the agent two seconds to cancel, then ends the processes it can attribute to that agent,
including shell commands in separate process groups. The task stays Stopping until those known
processes have exited. Pressing Stop again ends the grace period.
An agent process can serve several tasks: Native waits for its other tasks to finish or be stopped
before ending that shared process, and explains that commands may still be running meanwhile.
ACP cancellation does not guarantee that every command has exited or that commands cannot detach
between process snapshots. Native therefore reports an unverified Stop as a failed turn with a clear warning that
background commands may still be running, rather than labelling it Stopped. Queued messages remain
paused unless the user explicitly chose Send Now. In-app mode, which cannot track the host's processes,
keeps the turn Stopping and explains its limit.

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

| Keys | Action |
| --- | --- |
| @ | Open the file list |
| ↑ / ↓ | Move the selection |
| Return or Tab | Insert the selected file or folder, then a space, with the caret after it |
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

With the All in view sidebar experiment, the ⌘Y keycap marks that visible task's oldest tool
approval, provided it offers Allow once. Questions and requests in other tasks have no keycap.
Global routing through Peek is a later slice.

The oldest pending request in the visible task answers these: a tool's permission request, a
workflow step waiting for approval, or an expedition's route (or route change) waiting for review.
They're chosen not to collide with text editing in the composer.

| Keys | Action |
| --- | --- |
| ⌘Y | Allow once (approve the workflow step) |
| ⌥⌘Y | Allow always (when offered) |
| ⌘⇧⌫ | Reject |

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
| ⌘N | New task with the last-used agent | File | `session.new` |
| ⌥⌘N | New task with… (agent picker) | File | `session.newWithAgent` |
| ⌥⌘E | New expedition (`docs/expeditions.md`) | File | `expedition.new` |
| ⌘O | Open folder | File | `project.open` |
| | The current project's settings (Settings ▸ Projects; also in the project's menu in the sidebar) | File | `project.settings` |
| | Refresh git and pull-request state for every task in the current project (also Refresh in its sidebar menu) | File | `project.refresh` |
| | Clean up the current project's merged task worktrees, branches and stale worktree records, after a review (also "Clean Up Merged…" in the project's menu in the sidebar) | File | `git.cleanUpMerged` |
| ⇧⌘O | Open the task's folder in the default app (Open In) | Task | `session.openInDefaultApp` |
| ⌥⌘P | Open the task's pull request, where clicking one goes (Settings ▸ GitHub); listed while its branch has one | Task | `pullRequest.openForTask` |
| ⌘L | Focus the composer | Task | `composer.focus` |
| ⌘[ / ⌘] | Back / forward through the tasks you've viewed | Go | `go.back` / `go.forward` |
| ⌘1 – ⌘9 | Go to the Nth task in the sidebar | Task | `session.select1` – `session.select9` |
| ⌃Tab / ⌃⇧Tab | Next / previous task | Task | `session.next` / `session.previous` |
| Return on a selected sidebar task | Rename it (Escape cancels, Return commits) | Task | |
| ⌃⌘S | Show or hide the sidebar | View | `view.toggleSidebar` |
| ⌥⌘↑ / ⌥⌘↓ | Move the selected project or task up / down (a queued message instead, while one is open in the composer) | Task | `sidebar.moveUp` / `sidebar.moveDown` |
| ⌘Z / ⇧⌘Z | Undo / redo the window's latest change, newest first: typing, or archiving, renaming, pinning or deleting a task or project (a deletion until it's carried out). The undo toast's Undo takes back the same change, once | Edit | |
| ⇧⌘A | Archive the selected task and open the next task in the sidebar's current filter and sort order (or the previous task at the end). ⌘Z or the toast's Undo restores and reopens it. Unarchive an archived task; with several tasks picked, archive them all | Task | `session.archive` |
| ⌥⌘J | Turn the sidebar's Needs you filter on or off (its filter menu has the rest) | View | `view.needsYouFilter` |
| ⌘⇧P | Pull requests | Go | `go.pullRequests` |
| | GitHub Account: open the sidebar account menu (Mac only) | Go | `github.accounts` |
| Tab, then Space on the sidebar account | Open the account menu; arrow keys select, Return chooses, Escape closes | | |
| ⌘⇧X | Expeditions | Go | `go.expeditions` |
| ⇧⌘F | Search every task (`docs/search.md`) | Go | `search.show` |
| ⌥⌘I | Show or hide the subagent inspector | View | `view.toggleSubagentInspector` |
| ⌘⇧D | Show or hide the changes inspector (the task's uncommitted git changes) | View | `view.toggleChanges` |
| ⌃⌘M | Show the task's MCP servers (the server chip beside the composer's context ring) | View | `view.mcpServers` |
| ⌃⌘A | Keep Mac awake: cycle Off → While agents work → On (View ▸ Keep Mac Awake) | View | `keepAwake.nextMode` |
| | Show or hide the status bar along the window's bottom edge (on by default) | View | `statusBar.toggle` |

## Home Next (Labs)

With Next enabled in Settings > Labs, Home shows one ask at a time. The visible approval owns
the usual permission keys: Cmd-Y allows once, Option-Cmd-Y always allows when offered, and
Shift-Cmd-Delete rejects. Tab and Space reach Up next, Open Task, the ordering menu, and Show
more. Cmd-Return opens the current ask's task; Shift-Cmd-Down shows the next five rows.
Cmd-N starts a task and Cmd-O opens a folder, including before the first project exists.

## Task tools (Labs)

With Task Tools enabled in Settings ▸ Labs (off by default), the Changes fact under the title
opens the changes panel. It docks beside a wide conversation and overlays a narrow one.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌥⌘1 | Show or hide Changes | View ▸ Tools | `sessionTools.changes` |
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

## Picking tasks in the sidebar

Several tasks can be picked at once and acted on together. While more than one is picked (or Select
Tasks is on, which makes taps pick, for touch), a bar at the foot of the sidebar says how many, with
Archive, Mark as Read, Delete and the rest under More; a picked task's context menu offers the same.
Each action applies to the picked tasks it would change and offers one Undo for all of them; Delete
asks first.

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
| | Delete the picked tasks (asks first; Undo for a few seconds) | Task ▸ Selected Tasks | `selection.delete` |
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

With the Quiet composer experiment enabled, each setting is a plain-word button under the draft.
The same keys below still apply. The agent name opens New Task With (⌥⌘N), or Change Agent
when that experiment is also enabled. Tab reaches the buttons, Space opens their pickers, and
Escape closes a picker.

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘⇧M | Next permission mode | Task | `session.nextPermissionMode` |
| ⌃⇧M | Next mode: Build, Plan, Ask, Debug, Review, then your own modes and the project's (the composer's Mode pill) | Task ▸ Mode | `session.nextMode` |
| | Put the task in a mode, one command per mode ("Debug Mode"); your own and the project's modes get theirs too | Task ▸ Mode | `mode.build` / `mode.plan` / `mode.ask` / `mode.debug` / `mode.review` |
| | Edit Modes… (Settings ▸ Modes) | Task ▸ Mode | `modes.edit` |
| ⌘⇧E | Model picker | Task | `session.chooseModel` |
| ⌥⌘G | Set or edit the task's goal | Task | `goal.edit` |
| ⌥⌘R | Run a workflow | Task | `workflow.run` |

## Choosing an agent

With Change Agent enabled in Settings > Labs, Task > Change Agent and the command palette
(`session.changeAgent`) prepare a handoff to another installed agent. The task's agent control
and sidebar menu offer the same action. Review and edit the handoff, choose the agent and model,
then use Change Agent and Send. Cancel keeps the current task. A running turn must finish first.
This first slice supports tasks on this Mac; earlier transcripts stay under Earlier Conversation.
There is no default shortcut.

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
| ⌘F | Focus the search field |
| ↑ / ↓ | Move through the search results |
| Return | Open the highlighted result |
| Escape | Clear the search; with it empty, close Settings |
| ⌘[ | Close Settings, back to where you were (Go menu) |
| ↑ / ↓ in the page list | Move to the previous / next page |

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
