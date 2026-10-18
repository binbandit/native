import Foundation
import Testing

@testable import NativeCommands

@Suite struct KeyShortcutTests {
    @Test func glyphsAndWordsParseToTheSameShortcut() throws {
        let archive = try #require(KeyShortcut("⇧⌘A"))
        #expect(KeyShortcut("⌘⇧A") == archive)
        #expect(KeyShortcut("shift+cmd+a") == archive)
        #expect(KeyShortcut("Command + Shift + A") == archive)
        #expect(archive.key == .character("a"))
        #expect(archive.modifiers == [.command, .shift])
    }

    @Test func specialKeysUseTheDocsNames() {
        #expect(KeyShortcut("⌃Tab") == KeyShortcut(.tab, modifiers: .control))
        #expect(KeyShortcut("⌘⇧⌫") == KeyShortcut(.delete, modifiers: [.command, .shift]))
        #expect(KeyShortcut("⌥⌘↑") == KeyShortcut(.upArrow, modifiers: [.command, .option]))
        #expect(KeyShortcut("⌘Return") == KeyShortcut(.return, modifiers: .command))
        #expect(KeyShortcut("⌘↩") == KeyShortcut("cmd+enter"))
        #expect(KeyShortcut("ctrl+`") == KeyShortcut(.character("`"), modifiers: .control))
        #expect(KeyShortcut("cmd++") == KeyShortcut(.character("+"), modifiers: .command))
    }

    @Test func printsLikeTheMenuBarAndSpellsInWords() throws {
        let shortcut = try #require(KeyShortcut("⌘⇧⌥⌃k"))
        #expect(shortcut.displayString == "⌃⌥⇧⌘K")
        #expect(shortcut.serialized == "ctrl+opt+shift+cmd+k")
        #expect(KeyShortcut(shortcut.serialized) == shortcut)
        #expect(KeyShortcut("⌃⇧Tab")?.displayString == "⌃⇧⇥")
    }

    @Test func rejectsWhatIsNotAShortcut() {
        #expect(KeyShortcut("") == nil)
        #expect(KeyShortcut("⌘") == nil)
        #expect(KeyShortcut("cmd+") == nil)
        #expect(KeyShortcut("cmd+ab") == nil)
        #expect(KeyShortcut("hyper+a") == nil)
    }

    @Test func codableAsItsSpelling() throws {
        let shortcut = try #require(KeyShortcut("⌥⌘A"))
        let data = try JSONEncoder().encode([shortcut])
        #expect(String(decoding: data, as: UTF8.self) == #"["opt+cmd+a"]"#)
        #expect(try JSONDecoder().decode([KeyShortcut].self, from: data) == [shortcut])
    }

    @Test func searchFindsItBySpokenNames() throws {
        let terms = try #require(KeyShortcut("⇧⌘↩")).searchTerms
        #expect(terms.contains("⇧⌘↩"))
        #expect(terms.contains("command") && terms.contains("shift") && terms.contains("enter"))
    }

    @Test func reservedShortcutsAndBareKeysAreRejected() throws {
        #expect(ReservedShortcuts.rejection(for: try #require(KeyShortcut("⌘C"))) == .reserved("Copy"))
        #expect(ReservedShortcuts.rejection(for: try #require(KeyShortcut("⌥A"))) == .needsCommandOrControl)
        #expect(ReservedShortcuts.rejection(for: try #require(KeyShortcut("⌥⌘A"))) == nil)
        #expect(ReservedShortcuts.owners.count == ReservedShortcuts.table.count)
    }
}
