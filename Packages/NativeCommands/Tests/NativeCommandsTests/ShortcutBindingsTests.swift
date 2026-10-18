import Foundation
import Testing

@testable import NativeCommands

@Suite struct ShortcutBindingsTests {
    private let archive: CommandID = "session.archive"
    private let keepAwake: CommandID = "keepAwake.nextMode"
    private let rename: CommandID = "session.rename"

    private func key(_ text: String) throws -> KeyShortcut {
        try #require(KeyShortcut(text))
    }

    @Test func defaultsUntilChanged() throws {
        var bindings = ShortcutBindings()
        #expect(bindings.shortcut(for: archive) == (try key("⇧⌘A")))
        bindings.assign(try key("⌥⌘A"), to: archive)
        #expect(bindings.shortcut(for: archive) == (try key("⌥⌘A")))
        #expect(bindings.isCustomized(archive))
        // Choosing the default again isn't a change.
        bindings.assign(try key("⇧⌘A"), to: archive)
        #expect(!bindings.isCustomized(archive))
    }

    @Test func removingAShortcutIsAChange() {
        var bindings = ShortcutBindings()
        bindings.assign(nil, to: archive)
        #expect(bindings.shortcut(for: archive) == nil)
        #expect(bindings.propertyList == ["session.archive": ""])
        bindings.reset(archive)
        #expect(bindings.shortcut(for: archive) != nil)
    }

    @Test func conflictsNameTheOtherCommand() throws {
        let bindings = ShortcutBindings()
        #expect(bindings.conflict(for: try key("⌃⌘A"), assigningTo: archive) == keepAwake)
        #expect(bindings.conflict(for: try key("⇧⌘A"), assigningTo: archive) == nil)
    }

    @Test func replaceLeavesTheOtherWithout() throws {
        var bindings = ShortcutBindings()
        bindings.assign(try key("⌃⌘A"), to: archive, resolving: .replace)
        #expect(bindings.shortcut(for: archive) == (try key("⌃⌘A")))
        #expect(bindings.shortcut(for: keepAwake) == nil)
    }

    @Test func swapGivesTheOtherTheOldShortcut() throws {
        var bindings = ShortcutBindings()
        bindings.assign(try key("⌃⌘A"), to: archive, resolving: .swap)
        #expect(bindings.shortcut(for: keepAwake) == (try key("⇧⌘A")))
        #expect(bindings.commands(boundTo: try key("⌃⌘A")) == [archive])
    }

    @Test func commandsWithoutDefaultsCanTakeShortcuts() throws {
        var bindings = ShortcutBindings()
        bindings.assign(try key("⌃⌘R"), to: rename)
        #expect(bindings.shortcut(for: rename) == (try key("⌃⌘R")))
        #expect(bindings.propertyList == ["session.rename": "ctrl+cmd+r"])
    }

    @Test func propertyListRoundTrips() throws {
        var bindings = ShortcutBindings()
        bindings.assign(try key("⌥⌘A"), to: archive)
        bindings.assign(nil, to: keepAwake)
        let restored = ShortcutBindings(propertyList: bindings.propertyList)
        #expect(restored == bindings)
        // Unreadable entries and ones that match the default are dropped.
        #expect(ShortcutBindings(propertyList: ["session.archive": "nonsense"]).overrides.isEmpty)
        #expect(ShortcutBindings(propertyList: ["session.archive": "shift+cmd+a"]).overrides.isEmpty)
    }

    @Test func fileRoundTrips() throws {
        var bindings = ShortcutBindings()
        bindings.assign(try key("⌥⌘A"), to: archive)
        let data = try ShortcutFile.encode(bindings)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""session.archive" : "opt+cmd+a""#))
        #expect(try ShortcutFile.decode(data) == ["session.archive": "opt+cmd+a"])
    }

    @Test func fileErrors() {
        #expect(throws: ShortcutFileError.unreadable) { try ShortcutFile.decode(Data("{}".utf8)) }
        let newer = #"{"format": "native-shortcuts", "version": 99, "shortcuts": {}}"#
        #expect(throws: ShortcutFileError.newerVersion) { try ShortcutFile.decode(Data(newer.utf8)) }
    }

    @Test func importKeepsWhatCanBeApplied() throws {
        let known: Set<CommandID> = [archive, keepAwake, rename, "palette.show"]
        let result = ShortcutBindings().importing(
            [
                "session.archive": "opt+cmd+a",
                "session.rename": "cmd+c",
                "keepAwake.nextMode": "nonsense",
                "missing.command": "cmd+j",
                "palette.show": "",
            ], knownCommands: known)
        #expect(result.bindings.shortcut(for: archive) == (try key("⌥⌘A")))
        #expect(result.bindings.shortcut(for: "palette.show") == nil)
        #expect(result.applied == ["palette.show", archive])
        #expect(
            result.skipped.map(\.reason) == [
                .unreadable("nonsense"), .unknownCommand, .rejected(try key("⌘C"), .reserved("Copy")),
            ])
    }

    @Test func importSkipsCollisionsButAllowsSwaps() throws {
        let known: Set<CommandID> = [archive, keepAwake, rename]
        let swapped = ShortcutBindings().importing(
            ["session.archive": "ctrl+cmd+a", "keepAwake.nextMode": "shift+cmd+a"], knownCommands: known)
        #expect(swapped.skipped.isEmpty)
        #expect(swapped.bindings.shortcut(for: keepAwake) == (try key("⇧⌘A")))

        let colliding = ShortcutBindings().importing(["session.rename": "ctrl+cmd+a"], knownCommands: known)
        #expect(colliding.skipped == [.init(command: rename, reason: .conflict(try key("⌃⌘A"), keepAwake))])
        #expect(colliding.bindings.overrides.isEmpty)
    }
}
