import Foundation

/// A named command a project runs with one click: "Test" runs `bun run test` in the task's worktree.
/// The user's own live in Native's settings; a team's come from the repo (`ProjectActionFile`).
public struct ProjectAction: Identifiable, Hashable, Sendable {
    public var id: ID
    public var name: String
    /// What runs, with the user's shell, exactly as it would be typed in a terminal.
    public var command: String
    /// An SF Symbol; nil shows the default glyph.
    public var icon: String?
    public var directory: Directory
    public var presentation: Presentation

    public init(
        id: ID = .yours(),
        name: String,
        command: String,
        icon: String? = nil,
        directory: Directory = .worktree,
        presentation: Presentation = .terminal
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.icon = icon
        self.directory = directory
        self.presentation = presentation
    }

    /// The user's own actions get a fresh id; a repo file's are named after their entry, so they
    /// stay the same across reads (Run Last remembers one).
    public struct ID: Hashable, Sendable, Codable, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func yours() -> Self {
            Self(rawValue: "own:\(UUID().uuidString)")
        }

        static func repository(_ key: String) -> Self {
            Self(rawValue: "repo:\(key)")
        }

        public var isFromRepository: Bool {
            rawValue.hasPrefix("repo:")
        }

        public var description: String { rawValue }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// Where the output goes: a terminal tab named after the action, or nowhere until it finishes,
    /// when a toast says how it went.
    public enum Presentation: String, Hashable, Sendable, Codable, CaseIterable {
        case terminal
        case background
    }

    /// The folder the command starts in: a path relative to the task's worktree (what the agent
    /// works in) or to the project's own checkout.
    public struct Directory: Hashable, Sendable {
        public enum Base: String, Hashable, Sendable, Codable, CaseIterable {
            case worktree
            case project
        }

        public var base: Base
        /// Relative to `base`; empty for the folder itself.
        public var path: String

        public init(base: Base, path: String = "") {
            self.base = base
            self.path = path
        }

        public static let worktree = Self(base: .worktree)

        /// The folder, given the task's worktree and the project's checkout. A path that tries to
        /// climb out of its base (`../..`) stays in the base.
        public func resolved(worktree: URL, project: URL) -> URL {
            let root = base == .worktree ? worktree : project
            let relative = path.split(separator: "/").filter { !$0.isEmpty && $0 != "." }
            guard !relative.isEmpty, !relative.contains("..") else { return root }
            return relative.reduce(root) { $0.appending(path: String($1), directoryHint: .isDirectory) }
        }
    }
}

extension ProjectAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, command, icon, directory, relativeTo, runIn
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        let base = try container.decodeIfPresent(String.self, forKey: .relativeTo).flatMap(Directory.Base.init)
        directory = Directory(
            base: base ?? .worktree, path: try container.decodeIfPresent(String.self, forKey: .directory) ?? "")
        presentation =
            try container.decodeIfPresent(String.self, forKey: .runIn).flatMap(Presentation.init) ?? .terminal
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(icon, forKey: .icon)
        if !directory.path.isEmpty {
            try container.encode(directory.path, forKey: .directory)
        }
        if directory.base != .worktree {
            try container.encode(directory.base.rawValue, forKey: .relativeTo)
        }
        try container.encode(presentation.rawValue, forKey: .runIn)
    }
}

extension ProjectAction {
    /// A stable, lower camel case key for the action's name ("Compose Up" is `composeUp`), so a
    /// shortcut given to "Run: Test" runs every project's Test. Nil for a name with no letters or
    /// digits.
    public static func key(forName name: String) -> String? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = words.first else { return nil }
        return first + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    public var key: String? {
        Self.key(forName: name)
    }

    /// `name`, or "Name 2", "Name 3"... when another action already has that key.
    public static func uniqueName(_ name: String, among existing: [ProjectAction]) -> String {
        let taken = Set(existing.compactMap(\.key))
        guard let key = key(forName: name), taken.contains(key) else { return name }
        return (2...).lazy.map { "\(name) \($0)" }.first { !taken.contains(Self.key(forName: $0) ?? "") } ?? name
    }

    /// The command with its whitespace collapsed, for telling whether two commands are the same.
    static func normalized(_ command: String) -> String {
        command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
