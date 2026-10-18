# Keyboard

Native is fully usable from the keyboard. This table is the single source of truth: every shortcut
here exists, appears in its menu (so it's discoverable and listed in the Keyboard Shortcuts sheet),
and nothing outside this table claims a key.

Standard macOS behavior comes for free and must not be broken: Tab / Shift-Tab move focus through
controls (with Full Keyboard Access on), arrow keys move within lists and menus, Space activates the
focused control, Escape dismisses popovers and sheets, ⌘W closes the window, ⌘Q quits, ⌘, opens
Settings in the main window (and closes it again). In every sheet and dialog, Return activates the default (highlighted) button and Escape
cancels, so those keys don't get rows of their own.

## Sending

| Keys | While the agent is idle | While the agent is working |
| --- | --- | --- |
| Return | Send | The preferred follow-up behavior (Settings: Queue or Steer) |
| ⌘Return | Send | The other follow-up behavior |
| Shift-Return, Option-Return | New line | New line |
| Escape | Close the slash-command list if open | Stop the turn (with the slash-command list closed) |
| ⌘. | | Stop the turn |
| ↑ in an empty composer | Recall the last prompt | Edit the last queued message |

**Queue** holds the message as a chip above the composer and sends it when the turn ends; queued
messages go out one per turn, in order. Chips can be edited, removed, or steered into the running
turn right away. **Steer** adds the message to the running turn (`_session/steering`); agents that
don't support steering queue it instead, and the hint says so.

The composer always shows the current mapping as a hint while the agent works, e.g.
"↩ Queue · ⌘↩ Steer".

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

| Keys | Action | Menu |
| --- | --- | --- |
| ⌘N | New session with the last-used agent | File |
| ⌥⌘N | New session with… (agent picker) | File |
| ⌥⌘E | New expedition (`docs/expeditions.md`) | File |
| ⌘O | Open folder | File |
| ⇧⌘O | Open the task's folder in the default app (Open In) | Session |
| ⌘L | Focus the composer | Session |
| ⌘[ / ⌘] | Back / forward through the sessions you've viewed | Go |
| ⌘1 – ⌘9 | Go to the Nth session in the sidebar | Session |
| ⌃Tab / ⌃⇧Tab | Next / previous session | Session |
| Return on a selected sidebar session | Rename it (Escape cancels, Return commits) | Session |
| ⌃⌘S | Show or hide the sidebar | View |
| ⌥⌘↑ / ⌥⌘↓ | Move the selected project or session up / down | Session |
| ⇧⌘A | Archive the selected task (Undo brings it back) | Session |
| ⌥⌘J | Show only tasks that need you | View |
| ⌘⇧P | Pull requests | Go |
| ⌘⇧X | Expeditions | Go |
| ⌥⌘I | Show or hide the subagent inspector | View |
| ⌘⇧D | Show or hide the changes inspector (the task's uncommitted git changes) | View |
| ⌃⌘M | Show the session's MCP servers | View |
| ⌃⌘A | Keep Mac awake: cycle Off → While agents work → On (View ▸ Keep Mac Awake) | View |

## Session settings

| Keys | Action | Menu |
| --- | --- | --- |
| ⌘⇧M | Next permission mode | Session |
| ⌘⇧E | Model picker | Session |
| ⌥⌘G | Set or edit the session's goal | Session |
| ⌥⌘R | Run a workflow | Session |

## Settings

| Keys | Action |
| --- | --- |
| ⌘F | Focus the search field |
| ↑ / ↓ | Move through the search results |
| Return | Open the highlighted result |
| Escape | Clear the search; with it empty, close Settings |
| ⌘[ | Close Settings, back to where you were (Go menu) |
| ↑ / ↓ in the page list | Move to the previous / next page |

## Terminal

Each task has a terminal panel under the composer, opening in the task's folder (`docs/terminal.md`).

| Keys | Action | Menu |
| --- | --- | --- |
| ⌃` | Show the task's terminal and focus it; with the terminal focused, hide it and return to the composer | View |
| ⌃⇧` | New terminal tab | View |
| | Close the terminal tab (asks first when a program is running in it) | View |

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

## Ownership

Menu commands live in `NativeApp`; composer keys in `native/Views/Composer*`; permission keys in
`native/Views/Transcript/ToolCallView.swift`; sidebar keys in `SidebarView`; Settings keys in
`SettingsScreen` and `SettingsSearchField`; terminal commands in
`native/Terminal/Views/TerminalCommands.swift` and keys inside a terminal in
`GhosttyConfiguration.keybinds` (`Packages/Terminal`). Change a key here first, then in code.

## Celebrations

| Keys | Action |
| --- | --- |
| ⌥⇧⌘H | Restore the usual icon and Home while a celebration shows (skips it until it next occurs), or bring a skipped one back (View menu) |
