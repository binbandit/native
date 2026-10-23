/// Native's default shortcuts, by command. `docs/keyboard.md` is the source of truth: change a key
/// there first, then here. `KeyboardDocumentTests` fails when the two disagree, and no two
/// commands may share a default.
public enum DefaultShortcuts {
    public static let all: [CommandID: KeyShortcut] = table.compactMapValues(KeyShortcut.init)

    /// As `docs/keyboard.md` writes them. Every entry must parse (a test checks).
    static let table: [CommandID: String] = [
        // Sessions and navigation
        "session.new": "⌘N",
        "session.newWithAgent": "⌥⌘N",
        "expedition.new": "⌥⌘E",
        "project.open": "⌘O",
        "session.openInDefaultApp": "⇧⌘O",
        "pullRequest.openForTask": "⌥⌘P",
        "composer.focus": "⌘L",
        "go.back": "⌘[",
        "go.forward": "⌘]",
        "session.select1": "⌘1",
        "session.select2": "⌘2",
        "session.select3": "⌘3",
        "session.select4": "⌘4",
        "session.select5": "⌘5",
        "session.select6": "⌘6",
        "session.select7": "⌘7",
        "session.select8": "⌘8",
        "session.select9": "⌘9",
        "session.next": "⌃Tab",
        "session.previous": "⌃⇧Tab",
        "view.toggleSidebar": "⌃⌘S",
        "sidebar.moveUp": "⌥⌘↑",
        "sidebar.moveDown": "⌥⌘↓",
        "session.archive": "⇧⌘A",
        "view.needsYouFilter": "⌥⌘J",
        "go.pullRequests": "⇧⌘P",
        "go.expeditions": "⇧⌘X",
        "view.toggleSubagentInspector": "⌥⌘I",
        "view.toggleChanges": "⇧⌘D",
        "sessionTools.changes": "⌥⌘1",
        "taskWell.toggle": "⌘I",
        "taskWell.terminal": "⌥⌘2",
        "taskWell.dev": "⌥⌘3",
        "taskWell.subagents": "⌥⌘4",
        "taskWell.pullRequest": "⌥⌘5",
        "view.mcpServers": "⌃⌘M",
        "keepAwake.nextMode": "⌃⌘A",
        "palette.show": "⌘K",
        "help.keyboardShortcuts": "⌘/",
        "search.show": "⇧⌘F",
        // Session settings
        "session.nextPermissionMode": "⇧⌘M",
        "session.nextMode": "⌃⇧M",
        "session.chooseModel": "⇧⌘E",
        "goal.edit": "⌥⌘G",
        "workflow.run": "⌥⌘R",
        // Sending and attachments
        "session.stop": "⌘.",
        "composer.attachFiles": "⌘U",
        // Terminal
        "terminal.toggle": "⌃`",
        "terminal.newTab": "⌃⇧`",
        // Project actions
        "projectActions.runLast": "⇧⌘R",
        "projectActions.stop": "⇧⌘.",
        // Celebrations
        "celebration.restore": "⌥⇧⌘H",
        // Quitting
        "app.quitAndStopAgents": "⌃⌥⌘Q",
    ]
}
