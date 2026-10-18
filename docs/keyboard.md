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
focused control, Escape dismisses popovers and sheets, ⌘W closes the window, ⌘Q quits, ⌘, opens
Settings in the main window (and closes it again). In every sheet and dialog, Return activates the default (highlighted) button and Escape
cancels, so those keys don't get rows of their own.

## Sending

| Keys | While the agent is idle | While the agent is working | Command |
| --- | --- | --- | --- |
| Return | Send | The preferred follow-up behavior (Settings: Queue or Steer) | |
| ⌘Return | Send | The other follow-up behavior | |
| Shift-Return, Option-Return | New line | New line | |
| Escape | Close the slash-command list if open | Stop the turn (with the slash-command list closed) | |
| ⌘. | | Stop the turn | `session.stop` |
| ↑ in an empty composer | Recall the last prompt | Edit the last queued message | |

**Queue** holds the message as a chip above the composer and sends it when the turn ends; queued
messages go out one per turn, in order. Chips can be edited, removed, or steered into the running
turn right away. **Steer** adds the message to the running turn (`_session/steering`); agents that
don't support steering queue it instead, and the hint says so.

The composer shows the current mapping as a hint while the agent works, e.g.
"↩ Queue · ⌘↩ Steer", when the controls row has room for it; the placeholder always says what
Return does.

## Agent questions

When an agent asks structured questions (Claude Code's AskUserQuestion, ACP form elicitation), they
dock above the composer as a card: the question, a `1/3` pager, options, a free-text row, and Skip /
Next. The card takes focus when it appears and the composer is empty. Plain digits pick options
only while the card has focus; ⌘1 – ⌘9 stay session navigation.

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
| Type | Narrow the list; letters in order match too (`nwse` finds New Session) |
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
| ⌘Return in the setup-script editor | Save the script new worktrees run (Settings ▸ Git) |

## Pull request page

| Keys | Action |
| --- | --- |
| ⌘Return in a comment box | Send it: comment, reply, add to the review, or save an edit |
| Escape in a new line comment | Discard it |
| Click a line number | Comment on that line |
| Drag across line numbers | Comment on the lines dragged over, within one hunk and one side (on iPad: touch and hold a line number, then drag) |
| Shift-click a line number | Widen the line comment to a range (on iPad: "Extend Comment to Here" in the line's menu) |
| Return in the review sheet | Submit the review (merging always takes a click) |
| Escape in the review or merge sheet | Close it without submitting |

## Slash commands

| Keys | Action |
| --- | --- |
| / at the start of the composer | Open the command list |
| ↑ / ↓ | Move the selection |
| Return or Tab | Insert the selected command |
| Escape | Close the list |

## File mentions

Typing `@` at the start of a word lists the project's files (ignored files left out; changed and
recently mentioned files first), narrowing as you type. The chosen file goes into the draft as
`@path`. Pasted or dictated `@` text opens the list the same way ([accessibility.md](accessibility.md)).

| Keys | Action |
| --- | --- |
| @ | Open the file list |
| ↑ / ↓ | Move the selection |
| Return or Tab | Insert the selected file |
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
| Delete on a chip | Remove it from the message | | |
| Delete in an empty draft | Remove the last file (a held key doesn't) | | |
| ⌘Z | Put back a removed file | Edit | |

## Permission requests

The oldest pending request in the visible session answers these: a tool's permission request, a
workflow step waiting for approval, or an expedition's route (or route change) waiting for review.
They're chosen not to collide with text editing in the composer.

| Keys | Action |
| --- | --- |
| ⌘Y | Allow once (approve the workflow step) |
| ⌥⌘Y | Allow always (when offered) |
| ⌘⇧⌫ | Reject |

On an expedition's route review, ⌘Return approves too, and ⌘L focuses the message field for the
expedition's lead (the composer key, on a page without a composer).

## Sessions and navigation

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘K | Command palette: run any command, or jump to a task, project or Settings page | View | `palette.show` |
| ⌘N | New session with the last-used agent | File | `session.new` |
| ⌥⌘N | New session with… (agent picker) | File | `session.newWithAgent` |
| ⌥⌘E | New expedition (`docs/expeditions.md`) | File | `expedition.new` |
| ⌘O | Open folder | File | `project.open` |
| ⇧⌘O | Open the task's folder in the default app (Open In) | Session | `session.openInDefaultApp` |
| ⌘L | Focus the composer | Session | `composer.focus` |
| ⌘[ / ⌘] | Back / forward through the sessions you've viewed | Go | `go.back` / `go.forward` |
| ⌘1 – ⌘9 | Go to the Nth session in the sidebar | Session | `session.select1` – `session.select9` |
| ⌃Tab / ⌃⇧Tab | Next / previous session | Session | `session.next` / `session.previous` |
| Return on a selected sidebar session | Rename it (Escape cancels, Return commits) | Session | |
| ⌃⌘S | Show or hide the sidebar | View | `view.toggleSidebar` |
| ⌥⌘↑ / ⌥⌘↓ | Move the selected project or session up / down | Session | `sidebar.moveUp` / `sidebar.moveDown` |
| ⇧⌘A | Archive the selected task (Undo brings it back), or unarchive an archived one | Session | `session.archive` |
| ⌥⌘J | Show only tasks that need you | View | `view.needsYouFilter` |
| ⌘⇧P | Pull requests | Go | `go.pullRequests` |
| ⌘⇧X | Expeditions | Go | `go.expeditions` |
| ⇧⌘F | Search every task (`docs/search.md`) | Go | `search.show` |
| ⌥⌘I | Show or hide the subagent inspector | View | `view.toggleSubagentInspector` |
| ⌘⇧D | Show or hide the changes inspector (the task's uncommitted git changes) | View | `view.toggleChanges` |
| ⌃⌘M | Show the session's MCP servers (the server chip beside the composer's context ring) | View | `view.mcpServers` |
| ⌃⌘A | Keep Mac awake: cycle Off → While agents work → On (View ▸ Keep Mac Awake) | View | `keepAwake.nextMode` |

## Session settings

| Keys | Action | Menu | Command |
| --- | --- | --- | --- |
| ⌘⇧M | Next permission mode | Session | `session.nextPermissionMode` |
| ⌘⇧E | Model picker | Session | `session.chooseModel` |
| ⌥⌘G | Set or edit the session's goal | Session | `goal.edit` |
| ⌥⌘R | Run a workflow | Session | `workflow.run` |

## Settings

| Keys | Action |
| --- | --- |
| ⌘F | Focus the search field |
| ↑ / ↓ | Move through the search results |
| Return | Open the highlighted result |
| Escape | Clear the search; with it empty, close Settings |
| ⌘[ | Close Settings, back to where you were (Go menu) |
| ↑ / ↓ in the page list | Move to the previous / next page |

## Search

The search panel (⇧⌘F) keeps focus in its field, so typing always refines the search.

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
`native/Views/Transcript/ToolCallView.swift`; sidebar keys in `SidebarView`; Settings keys in
`SettingsScreen` and `SettingsSearchField`; search panel keys in `TranscriptSearchPanel`; terminal commands in
`native/Terminal/Views/TerminalCommands.swift` and keys inside a terminal in
`GhosttyConfiguration.keybinds` (`Packages/Terminal`). Change a key here first, then in code.

## Celebrations

| Keys | Action | Command |
| --- | --- | --- |
| ⌥⇧⌘H | Restore the usual icon and Home while a celebration shows (skips it until it next occurs), or bring a skipped one back (View menu) | `celebration.restore` |
