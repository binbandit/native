# Commands

Every user action Native has is a **command**, defined once and reachable three ways: from the menu
bar, from the command palette (⌘K), and by its keyboard shortcut. The user can rebind any command's
shortcut in Settings ▸ Keyboard Shortcuts, search by name or by keys, and export and import their
bindings. `docs/keyboard.md` lists the default shortcuts.

## The pieces

| Piece | Where | What it does |
| --- | --- | --- |
| `KeyShortcut`, `CommandID`, `ShortcutBindings`, `ShortcutFile`, `FuzzyMatch`, `DefaultShortcuts`, `ReservedShortcuts`, `KeyboardDocument` | `Packages/NativeCommands` | UI-free, tested: parsing and printing shortcuts, the defaults, resolving changes and conflicts, the export format, palette matching, and reading `docs/keyboard.md` |
| `NativeCommand` | `native/Commands/NativeCommand.swift` | One action: id, title, category, symbol, keywords, availability, perform, optional dynamic menu title, checkmark state, and a query action |
| `CommandRegistry` | `native/Commands/CommandRegistry.swift` | Every registered command, plus the bindings in effect: defaults, then the user's changes (or the organization's). Observable, so menus, the palette and Settings follow a change at once |
| `CommandContext` | `native/Commands/CommandContext.swift` | What a command acts on: the frontmost window's task and the window state views publish as focused scene values |
| `CommandMenuItem` | `native/Commands/CommandMenuItem.swift` | A command as a menu item, with its title, shortcut, availability and action all from the registry |
| `CommandPalette` | `native/Commands/Palette/` | The ⌘K palette's state, sources, ranking and view |
| Settings page | `native/Settings/Pages/KeyboardShortcutsSettingsPage.swift`, `native/Commands/Settings/` | Editing: recorder, conflicts, reset, search, import and export |
| Wiring | `native/Wiring/CommandsWiring.swift` | Registers every built-in feature's commands at launch and gives the palette its sources |

## A command

```swift
extension CommandID {
    static let sessionArchive: Self = "session.archive"
}

NativeCommand(.sessionArchive, title: "Archive Task", category: .tasks, systemImage: "archivebox") { context in
    guard let key = model.selection else { return }
    Task { await model.archiveSession(key, undoManager: context.undoManager) }
}
.available { _ in model.selection != nil }
```

- **The id is forever.** Preferences, exported files and configuration profiles store bindings by
  id, so never rename one; add a new id instead. Ids are `area.action` in lower camel case.
- **`perform` calls a model method**, so the companion app and the orchestration server can drive
  the same action. Views never talk to connections.
- **`available` decides everything.** An unavailable command is disabled in the menu and left out
  of the palette, and its key goes to whatever else wants it. ⌘K uses this to step aside while a
  terminal has focus, so the terminal's Clear keeps working.
- `menuTitle` gives the menu a state-dependent title ("Hide Sidebar"); `title` stays the stable
  name that Settings and search use. `toggles` adds a checkmark. `hiddenFromPalette` keeps
  menu-only commands (⌘1 – ⌘9) out of the palette. `takesQuery` makes the palette offer the
  command for whatever is typed ("Search Tasks for “…”").
- Features build their commands in their own folder, as a `NativeCommand` extension (for example
  `NativeCommand.terminal(_:)` in `native/Terminal/Views/TerminalCommands.swift`), and add one line
  to `CommandsWiring`. The menus place them with `CommandMenuItem(id, in: registry)`.

**A command with a shortcut needs a menu item.** The menu bar is what delivers key equivalents
(and what lists them, on the Mac and on iPad), so every command that can have a shortcut appears in
some menu. A menu item with its own presentation, such as the Fold Earlier Turns toggle backed by
`@AppStorage`, keeps its view and takes its shortcut from the registry with
`.keyboardShortcut(registry.keyboardShortcut(for:))`. Views that answer a key themselves read it
the same way (the composer's hidden Stop button).

## Shortcuts

- **Defaults** live in `DefaultShortcuts` and mirror `docs/keyboard.md`'s Command column.
  `KeyboardDocumentTests` fails when the two disagree, or when two commands share a default. Change
  the doc first, then the table.
- **The user's changes** are only the differences from the defaults, kept in user defaults under
  `policy.shortcuts.bindings` as `[command id: "shift+cmd+a"]`, with `""` for none. A command the
  user never touched follows the defaults as they change between versions.
- **The organization** can set the same key in a configuration profile (`docs/enterprise.md`).
  Its bindings then replace the user's, Settings ▸ Keyboard Shortcuts becomes read-only and says
  "Managed by your organization", and the user's own changes come back if the profile goes away.
- **Reserved keys** can't be assigned: macOS's standard shortcuts (⌘C, ⌘V, ⌘Q, ⌘W, ⌘,, ⌘Z and
  so on), which stay outside the registry, and the keys Native's views answer themselves
  (permission requests, ⌘Return in sheets, ⌘F). Every shortcut needs ⌘ or ⌃, so it never gets in
  the way of typing.
- **Notation.** Menus print shortcuts as glyphs in the menu bar's order (⌃⌥⇧⌘K). Files spell them
  in words (`ctrl+opt+shift+cmd+k`). Both parse, with the modifiers in any order, as do the names
  the docs use (`⌃Tab`, `⌘Return`, `Esc`).
- **No chords.** A two-step shortcut (⌘K then ⌘S) can't be a menu key equivalent, so the menu bar
  couldn't show or deliver it. That would need a key monitor of our own and break discoverability.
  With about 50 commands and the palette one key away, chords aren't worth that.

## Remapping in Settings

Settings ▸ Keyboard Shortcuts lists every command by category. Each shortcut is a pill:

- **Click it to record.** It shows the modifiers as they're held, and the next key completes the
  shortcut. Escape cancels, and Delete on its own removes the shortcut. On the Mac a local event
  monitor captures the keys before the menu bar sees them, so recording ⌘N doesn't start a session
  (`native/Platform/PlatformKeyRecorder.swift`). On iPad the focused pill listens with
  `onKeyPress`, and a key a menu claims runs its command instead.
- **Conflicts** name the other command and offer **Swap** (the other command takes this one's old
  shortcut), **Replace** (the other loses its shortcut) or **Cancel**.
- **A reserved or modifier-less key** is refused with the reason, and recording continues.
- **Reset** puts one command back on its default, through the same conflict check. **Reset All**
  asks first and suggests exporting.
- **Search** matches names, ids, categories and keywords. Typing a shortcut (`⌘K`, `cmd shift a`)
  or pressing one after clicking the keyboard button filters to the commands bound to it.
- **Export and import** use the user's changes as JSON. Import replaces the current changes. An entry
  is skipped, with the reason given, when it names an unknown command, can't be read, is reserved,
  or would collide; its command keeps its default.

```json
{ "format": "native-shortcuts", "version": 1, "shortcuts": { "session.archive": "opt+cmd+a" } }
```

Below the commands, the page lists the keys views answer themselves (composer, question card, lists,
Settings, inside a terminal), which can't be changed.

## The palette

⌘K opens it over the main window (View ▸ Command Palette…).

- It lists **commands** that can run now, with their shortcuts and checkmarks, plus the sidebar's
  **tasks**, the **projects** and every **Settings page**. Each kind comes from a
  `CommandPaletteSource`, so a feature can add a kind without touching the palette.
- **With nothing typed** it shows what was run recently, a few tasks, then everything else by kind.
  **With text** it ranks with `FuzzyMatch`, in tiers as the reference app's palette ranks them: the whole
  title, its start, a word's start, its initials, anywhere, the keywords, then the letters in order
  (`nwse` finds New Session). Sections are ordered by their best match, and recently used items move
  up within their tier, never into a better one.
- **Commands that take text** (`takesQuery`) appear last for any text, so the palette offers
  "Search Tasks for “…”" instead of searching transcripts itself (`native/Search`).
- ↑ / ↓ (or ⌃N / ⌃P) move, Return runs, Escape or a click outside closes. Rows grow to 44pt on
  touch. The palette reads the window's state when it opens and runs against it after closing, so
  focus is back in the window when the command acts.
- Recents are the last eight items run, by id (`commandPalette.recents`).

## Plugins

`CommandRegistry.register(_:)` takes commands at any time and replaces commands with the same id,
so a plugin can contribute commands later without changing the registry. A plugin's commands go in
the `.plugins` category, and their ids are prefixed with the plugin id (`my-plugin.doThing`). Their
defaults would come from the manifest rather than `DefaultShortcuts`. Since a command needs a menu
item to have a shortcut, a "Plugins" menu would place them. None of that is built yet. The
`NativePlugin` protocol would grow a `commands` capability, and manifest plugins could declare
commands that run a workflow or a script.

## Still to move

These keys are still answered by their views. They're reserved, so commands can't take them:

- Permission requests (⌘Y, ⌥⌘Y, ⇧⌘⌫ in `ToolCallView`, `WorkflowApprovalCard`, `RouteReviewView`,
  `ExpeditionOverview`). Moving them needs a session-level "answer the oldest request" model method.
- ⌘Return in sheets and the commit popover. These are sheet defaults, and they stay.
- ⌘L in an expedition's crew panel (the composer key on a page without a composer) should read
  `composer.focus` from the registry.

Hints that name a shortcut (sidebar items, tooltips, notices) read it from the registry with
`CommandRegistry.shared.help("Show Terminal", for: .terminalToggle)` or
`shortcut(for:)?.displayString`, so they follow a remap.
