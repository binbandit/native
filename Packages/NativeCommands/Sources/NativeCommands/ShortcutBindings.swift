/// The shortcut each command has: its default, unless the user (or their organization) changed it.
/// Only changes are kept, so a command the user never touched follows Native's defaults as they
/// change between versions.
public struct ShortcutBindings: Equatable, Sendable {
    public let defaults: [CommandID: KeyShortcut]
    /// Each changed command's shortcut, or nil where the user removed it.
    public private(set) var overrides: [CommandID: KeyShortcut?]

    public init(defaults: [CommandID: KeyShortcut] = DefaultShortcuts.all, overrides: [CommandID: KeyShortcut?] = [:]) {
        self.defaults = defaults
        self.overrides = overrides
    }

    /// The bindings a preferences dictionary describes ("session.archive": "opt+cmd+a", "" for
    /// none). Entries that don't parse are left out; `importing` reports them.
    public init(defaults: [CommandID: KeyShortcut] = DefaultShortcuts.all, propertyList: [String: String]) {
        self.init(defaults: defaults)
        for (id, text) in propertyList {
            if text.isEmpty {
                setOverride(nil, for: CommandID(id))
            } else if let shortcut = KeyShortcut(text) {
                setOverride(shortcut, for: CommandID(id))
            }
        }
    }

    /// The overrides as preferences and exported files keep them.
    public var propertyList: [String: String] {
        overrides.reduce(into: [:]) { list, entry in
            list[entry.key.rawValue] = entry.value?.serialized ?? ""
        }
    }

    public func shortcut(for id: CommandID) -> KeyShortcut? {
        if let override = overrides[id] {
            return override
        }
        return defaults[id]
    }

    public func isCustomized(_ id: CommandID) -> Bool {
        overrides.keys.contains(id)
    }

    /// Every command bound to `shortcut`, in id order.
    public func commands(boundTo shortcut: KeyShortcut) -> [CommandID] {
        Set(defaults.keys).union(overrides.keys).filter { self.shortcut(for: $0) == shortcut }.sorted()
    }

    /// The command that already has `shortcut`, if `id` were to take it.
    public func conflict(for shortcut: KeyShortcut, assigningTo id: CommandID) -> CommandID? {
        commands(boundTo: shortcut).first { $0 != id }
    }

    /// What happens to a command that already has the shortcut being assigned.
    public enum Resolution: Sendable {
        /// It takes the assigned command's old shortcut.
        case swap
        /// It's left without one.
        case replace
    }

    /// Gives `id` the shortcut (nil removes its shortcut), resolving a conflict as asked.
    public mutating func assign(_ shortcut: KeyShortcut?, to id: CommandID, resolving resolution: Resolution = .replace) {
        let previous = self.shortcut(for: id)
        if let shortcut {
            for other in commands(boundTo: shortcut) where other != id {
                setOverride(resolution == .swap ? previous : nil, for: other)
            }
        }
        setOverride(shortcut, for: id)
    }

    /// Puts `id` back on its default. The default may have gone to another command meanwhile:
    /// check `conflict(for:assigningTo:)` first, or use `assign(defaults[id], to: id, resolving:)`.
    public mutating func reset(_ id: CommandID) {
        overrides.removeValue(forKey: id)
    }

    /// Every command back on its default. Defaults never conflict with each other.
    public mutating func resetAll() {
        overrides.removeAll()
    }

    /// Records a change, or forgets it when it's the default anyway.
    mutating func setOverride(_ shortcut: KeyShortcut?, for id: CommandID) {
        if shortcut == defaults[id] {
            overrides.removeValue(forKey: id)
        } else {
            overrides.updateValue(shortcut, forKey: id)
        }
    }
}
