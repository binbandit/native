import Foundation
import NativeCommands
import NativePolicy
import Observation
import SwiftUI
import os

/// Every command Native has and the shortcut each is bound to now. The menu bar, the command
/// palette and Settings ▸ Keyboard Shortcuts all read it, so a change shows everywhere at once.
///
/// Bindings are the defaults (`DefaultShortcuts`, mirroring `docs/keyboard.md`) with the user's
/// changes on top, saved in preferences. An organization can set the bindings instead
/// (`docs/enterprise.md`); then the user's are set aside and Settings is read-only.
///
/// Views read it from the environment; AppKit menus built by hand read `CommandRegistry.shared`.
@MainActor
@Observable
final class CommandRegistry {
    static let shared = CommandRegistry()

    /// The preference the user's changes live under; an organization manages the same key.
    static let preferencesKey = "policy.shortcuts.bindings"

    /// In the order they were registered: each feature's, in the order the app adds them.
    private(set) var commands: [NativeCommand] = []
    private(set) var userBindings: ShortcutBindings

    @ObservationIgnored private var positions: [NativeCommand.ID: Int] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let policy: PolicyCenter
    /// The organization's bindings, parsed once per change of the managed value.
    @ObservationIgnored private var managedCache: (source: [String: String], bindings: ShortcutBindings)?
    @ObservationIgnored private let logger = Logger(subsystem: "Native", category: "Commands")

    init(defaults: UserDefaults = .standard, policy: PolicyCenter = .shared) {
        self.defaults = defaults
        self.policy = policy
        // A managed value shows through the defaults too; it isn't the user's.
        let saved =
            defaults.objectIsForced(forKey: Self.preferencesKey)
            ? [:] : defaults.dictionary(forKey: Self.preferencesKey) as? [String: String] ?? [:]
        userBindings = ShortcutBindings(propertyList: saved)
    }

    var bindings: ShortcutBindings {
        managedBindings ?? userBindings
    }

    /// The organization's bindings (`policy.shortcuts.bindings`), while it manages them.
    var managedBindings: ShortcutBindings? {
        let current = policy.policy
        guard current.isManaged(.shortcutBindings), let list = current.shortcutBindings else { return nil }
        if let managedCache, managedCache.source == list {
            return managedCache.bindings
        }
        let bindings = ShortcutBindings(propertyList: list)
        managedCache = (list, bindings)
        return bindings
    }

    /// Whether the organization decides the shortcuts.
    var isLocked: Bool {
        managedBindings != nil
    }

    // MARK: Commands

    /// Adds commands, replacing any with the same id (a plugin reloading its own, say).
    func register(_ newCommands: [NativeCommand]) {
        for command in newCommands {
            if let position = positions[command.id] {
                commands[position] = command
            } else {
                positions[command.id] = commands.count
                commands.append(command)
            }
        }
    }

    func command(_ id: NativeCommand.ID) -> NativeCommand? {
        positions[id].map { commands[$0] }
    }

    /// Runs a command if it can run now; returns whether it did.
    @discardableResult
    func perform(_ id: NativeCommand.ID, in context: CommandContext) -> Bool {
        guard let command = command(id), command.isAvailable(context) else { return false }
        command.perform(context)
        return true
    }

    /// Logs default shortcuts no feature registered a command for, which is usually a typo in an
    /// id. Call once every feature has registered.
    func reportUnregisteredDefaults() {
        let missing = DefaultShortcuts.all.keys.filter { positions[$0] == nil }.sorted()
        if !missing.isEmpty {
            logger.fault("No command registered for default shortcuts: \(missing.map(\.rawValue), privacy: .public)")
        }
    }

    // MARK: Shortcuts

    func shortcut(for id: NativeCommand.ID) -> KeyShortcut? {
        bindings.shortcut(for: id)
    }

    /// For SwiftUI's `.keyboardShortcut`, which takes nil for none.
    func keyboardShortcut(for id: NativeCommand.ID) -> KeyboardShortcut? {
        shortcut(for: id)?.keyboardShortcut
    }

    /// A tooltip or hint ending with the command's current shortcut, "Show Terminal (⌃`)", or just
    /// the text when it has none. Hints that name a key use this, so they follow a remap.
    func help(_ text: String, for id: NativeCommand.ID) -> String {
        shortcut(for: id).map { "\(text) (\($0.displayString))" } ?? text
    }

    func isCustomized(_ id: NativeCommand.ID) -> Bool {
        bindings.isCustomized(id)
    }

    /// The registered command that already has `shortcut`, if `id` were to take it.
    func conflict(for shortcut: KeyShortcut, assigningTo id: NativeCommand.ID) -> NativeCommand? {
        bindings.commands(boundTo: shortcut).lazy.filter { $0 != id }.compactMap { self.command($0) }.first
    }

    /// Why `shortcut` can't be bound to anything, in words, or nil when it can.
    func rejection(for shortcut: KeyShortcut) -> String? {
        switch ReservedShortcuts.rejection(for: shortcut) {
        case nil: nil
        case .needsCommandOrControl: "Add ⌘ or ⌃, so the shortcut doesn't get in the way of typing."
        case .reserved(let owner): "\(shortcut.displayString) is \(owner), which can't be changed."
        }
    }

    /// Binds `shortcut` to `id` (nil removes its shortcut). A command that had it gets `id`'s old
    /// shortcut (swap) or none (replace).
    func assign(_ shortcut: KeyShortcut?, to id: NativeCommand.ID, resolving resolution: ShortcutBindings.Resolution) {
        updateUserBindings { $0.assign(shortcut, to: id, resolving: resolution) }
    }

    func reset(_ id: NativeCommand.ID, resolving resolution: ShortcutBindings.Resolution = .replace) {
        updateUserBindings { $0.assign($0.defaults[id], to: id, resolving: resolution) }
    }

    func resetAll() {
        updateUserBindings { $0.resetAll() }
    }

    /// The user's changes as a file to keep or share.
    func exportedFile() throws -> Data {
        try ShortcutFile.encode(userBindings)
    }

    /// Replaces the user's changes with a file's, keeping what applies; returns what happened.
    func importFile(_ data: Data) throws(ShortcutFileError) -> ShortcutBindings.Import {
        let entries = try ShortcutFile.decode(data)
        let result = userBindings.importing(entries, knownCommands: Set(positions.keys))
        updateUserBindings { $0 = result.bindings }
        return result
    }

    private func updateUserBindings(_ change: (inout ShortcutBindings) -> Void) {
        guard !isLocked else { return }
        change(&userBindings)
        let list = userBindings.propertyList
        if list.isEmpty {
            defaults.removeObject(forKey: Self.preferencesKey)
        } else {
            defaults.set(list, forKey: Self.preferencesKey)
        }
    }
}
