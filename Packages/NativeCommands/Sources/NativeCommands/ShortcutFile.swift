import Foundation

/// Shortcuts exported to a file and imported back: the user's changes only, by command id.
///
///     { "format": "native-shortcuts", "version": 1, "shortcuts": { "session.archive": "opt+cmd+a" } }
///
/// An empty string removes a command's shortcut. An organization's configuration profile uses the
/// same dictionary (`docs/enterprise.md`, `policy.shortcuts.bindings`).
public enum ShortcutFile {
    public static let format = "native-shortcuts"
    public static let version = 1

    public static func encode(_ bindings: ShortcutBindings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Payload(format: format, version: version, shortcuts: bindings.propertyList))
    }

    /// The file's shortcuts dictionary, for `ShortcutBindings.importing`.
    public static func decode(_ data: Data) throws(ShortcutFileError) -> [String: String] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.format == format else {
            throw .unreadable
        }
        guard payload.version <= version else {
            throw .newerVersion
        }
        return payload.shortcuts
    }

    private struct Payload: Codable {
        var format: String
        var version: Int
        var shortcuts: [String: String]
    }
}

public enum ShortcutFileError: Error, Equatable, Sendable {
    /// Not a shortcuts file Native exported.
    case unreadable
    /// Exported by a newer Native.
    case newerVersion
}

extension ShortcutBindings {
    /// What importing a file did.
    public struct Import: Sendable {
        public var bindings: ShortcutBindings
        public var applied: [CommandID]
        public var skipped: [Skipped]
    }

    /// A file entry that wasn't applied, and why.
    public struct Skipped: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case unknownCommand
            case unreadable(String)
            case rejected(KeyShortcut, ReservedShortcuts.Rejection)
            /// Another command has the shortcut.
            case conflict(KeyShortcut, CommandID)
        }

        public var command: CommandID
        public var reason: Reason
    }

    /// The bindings `propertyList` describes in place of the current overrides, keeping only what
    /// can be applied: known commands, readable and allowed shortcuts, and no two commands on one
    /// shortcut (an entry that would collide is skipped and its command keeps its default).
    public func importing(_ propertyList: [String: String], knownCommands: Set<CommandID>) -> Import {
        var skipped: [Skipped] = []
        var accepted: [CommandID: KeyShortcut?] = [:]
        for (raw, text) in propertyList.sorted(by: { $0.key < $1.key }) {
            let id = CommandID(raw)
            guard knownCommands.contains(id) else {
                skipped.append(Skipped(command: id, reason: .unknownCommand))
                continue
            }
            if text.isEmpty {
                accepted.updateValue(nil, forKey: id)
                continue
            }
            guard let shortcut = KeyShortcut(text) else {
                skipped.append(Skipped(command: id, reason: .unreadable(text)))
                continue
            }
            if let rejection = ReservedShortcuts.rejection(for: shortcut) {
                skipped.append(Skipped(command: id, reason: .rejected(shortcut, rejection)))
                continue
            }
            accepted[id] = shortcut
        }

        // Dropping a colliding entry puts its command back on its default, which can collide in
        // turn, so repeat until nothing does. Each pass drops at least one entry.
        var result = ShortcutBindings(defaults: defaults)
        while true {
            result = ShortcutBindings(defaults: defaults)
            for (id, shortcut) in accepted {
                result.setOverride(shortcut, for: id)
            }
            let collision = accepted.keys.sorted().lazy.compactMap { id -> (CommandID, KeyShortcut, CommandID)? in
                guard let shortcut = result.shortcut(for: id),
                    let other = result.conflict(for: shortcut, assigningTo: id)
                else { return nil }
                return (id, shortcut, other)
            }.first
            guard let (id, shortcut, other) = collision else { break }
            accepted.removeValue(forKey: id)
            skipped.append(Skipped(command: id, reason: .conflict(shortcut, other)))
        }
        return Import(bindings: result, applied: accepted.keys.sorted(), skipped: skipped)
    }
}
