import Foundation
import Testing

@testable import NativeCommands

/// `docs/keyboard.md` is the source of truth for default shortcuts; these keep the code in step.
@Suite struct KeyboardDocumentTests {
    private func documentEntries() throws -> [KeyboardDocument.Entry] {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let markdown = try String(contentsOf: root.appending(path: "docs/keyboard.md"), encoding: .utf8)
        return try KeyboardDocument.entries(in: markdown)
    }

    @Test func defaultsMatchTheDocument() throws {
        let entries = try documentEntries()
        #expect(!entries.isEmpty)
        var documented: [CommandID: KeyShortcut] = [:]
        for entry in entries {
            #expect(
                DefaultShortcuts.all[entry.command] == entry.shortcut,
                "line \(entry.line): \(entry.command) is \(entry.shortcut?.displayString ?? "no shortcut") in the doc but \(DefaultShortcuts.all[entry.command]?.displayString ?? "none") in DefaultShortcuts"
            )
            documented[entry.command] = entry.shortcut
        }
        for (command, shortcut) in DefaultShortcuts.all where documented[command] == nil {
            Issue.record("\(command) (\(shortcut)) is in DefaultShortcuts but not in docs/keyboard.md")
        }
        #expect(Set(entries.map(\.command)).count == entries.count, "a command is listed twice")
    }

    @Test func everyDefaultParsesAndIsAllowed() {
        #expect(DefaultShortcuts.all.count == DefaultShortcuts.table.count)
        for (command, shortcut) in DefaultShortcuts.all {
            #expect(ReservedShortcuts.rejection(for: shortcut) == nil, "\(command) defaults to reserved \(shortcut)")
        }
    }

    @Test func noTwoCommandsShareADefault() {
        let byShortcut = Dictionary(grouping: DefaultShortcuts.all.keys) { DefaultShortcuts.all[$0] }
        for (shortcut, commands) in byShortcut where commands.count > 1 {
            Issue.record("\(shortcut.map(\.displayString) ?? "") is the default of \(commands.sorted())")
        }
    }

    @Test func parsesPairsRangesAndBlankKeys() throws {
        let markdown = """
            | Keys | Action | Command |
            | --- | --- | --- |
            | ⌘[ / ⌘] | Back / forward | `go.back` / `go.forward` |
            | ⌘1 – ⌘3 | Nth task | `session.select1` – `session.select3` |
            | | Close tab | `terminal.closeTab` |
            | Return | Not a command | |

            | Keys | Action |
            | --- | --- |
            | ⌘K | Ignored: no Command column |
            """
        let entries = try KeyboardDocument.entries(in: markdown)
        #expect(
            entries.map(\.command.rawValue) == [
                "go.back", "go.forward", "session.select1", "session.select2", "session.select3", "terminal.closeTab",
            ])
        #expect(entries[3].shortcut == KeyShortcut("⌘2"))
        #expect(entries[5].shortcut == nil)
    }

    @Test func reportsRowsItCannotRead() {
        let markdown = """
            | Keys | Command |
            | --- | --- |
            | ⌘[ / ⌘] | `go.back` |
            """
        #expect(throws: KeyboardDocument.ParseError(line: 3, problem: "2 keys for 1 commands")) {
            try KeyboardDocument.entries(in: markdown)
        }
    }
}
