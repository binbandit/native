import Foundation

/// An action Native offers from what it found in the project (a `test` script, a justfile recipe,
/// a Cargo.toml). Suggestions are only ever added or dismissed by the user, never run on their own.
public struct ProjectSuggestion: Identifiable, Hashable, Sendable {
    public let name: String
    public let command: String
    public let icon: String
    public let role: Role
    public let source: Source
    /// What the project says about it, such as a justfile recipe's doc comment.
    public let detail: String?
    public let presentation: ProjectAction.Presentation

    public init(
        name: String,
        command: String,
        role: Role,
        source: Source,
        detail: String? = nil,
        icon: String? = nil,
        presentation: ProjectAction.Presentation = .terminal
    ) {
        self.name = name
        self.command = command
        self.role = role
        self.source = source
        self.detail = detail
        self.icon = icon ?? role.icon
        self.presentation = presentation
    }

    /// The command, which is what dismissing remembers: the same command found again stays
    /// dismissed, whichever file it came from.
    public var id: String { ProjectAction.normalized(command) }

    /// The action adding it makes, named so it doesn't clash with `existing`.
    public func action(among existing: [ProjectAction]) -> ProjectAction {
        ProjectAction(
            name: ProjectAction.uniqueName(name, among: existing), command: command, icon: icon,
            presentation: presentation)
    }

    /// What an action does, which orders suggestions: the everyday ones first.
    public enum Role: Int, Hashable, Sendable, Comparable, CaseIterable {
        case install, test, dev, start, run, build, lint, typecheck, format, other

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// The usual name for an action in this role, when the project's own name is one of its
        /// spellings (`fmt` is Format).
        var title: String {
            switch self {
            case .install: "Install"
            case .test: "Test"
            case .dev: "Dev"
            case .start: "Start"
            case .run: "Run"
            case .build: "Build"
            case .lint: "Lint"
            case .typecheck: "Typecheck"
            case .format: "Format"
            case .other: "Run"
            }
        }

        var icon: String {
            switch self {
            case .install: "arrow.down.circle"
            case .test: "checkmark.seal"
            case .dev: "play.circle"
            case .start, .run: "play"
            case .build: "hammer"
            case .lint: "checklist"
            case .typecheck: "checkmark.shield"
            case .format: "text.alignleft"
            case .other: "terminal"
            }
        }

        /// The role a script, recipe or target of this name plays, if it's a well-known one.
        static func of(_ name: String) -> Self? {
            switch name.lowercased() {
            case "install", "setup", "bootstrap", "deps": .install
            case "test", "tests", "check-tests", "spec": .test
            case "dev", "develop", "serve", "watch": .dev
            case "start": .start
            case "run": .run
            case "build", "compile": .build
            case "lint", "clippy": .lint
            case "typecheck", "type-check", "types", "tsc", "check": .typecheck
            case "format", "fmt": .format
            default: nil
            }
        }
    }

    /// Where it was found, which breaks ties between roles: a project's own task runner first,
    /// since its recipes usually wrap the ecosystem's commands.
    public enum Source: Int, Hashable, Sendable, Comparable, CaseIterable {
        case justfile, makefile, packageJSON, cargo, swiftPackage, xcode, go, python, gradle, maven, dockerCompose

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// How the settings page names it: "From package.json".
        public var title: String {
            switch self {
            case .justfile: "justfile"
            case .makefile: "Makefile"
            case .packageJSON: "package.json"
            case .cargo: "Cargo.toml"
            case .swiftPackage: "Package.swift"
            case .xcode: "Xcode project"
            case .go: "go.mod"
            case .python: "Python project"
            case .gradle: "Gradle"
            case .maven: "pom.xml"
            case .dockerCompose: "Compose file"
            }
        }
    }
}

extension ProjectSuggestion {
    /// The suggestions worth showing: none already added (by command), none dismissed, no command
    /// twice, ordered by role (install, test, dev, ...), then by source, then as the project lists
    /// them.
    public static func visible(
        _ detected: [ProjectSuggestion], existing: [ProjectAction], dismissed: Set<String>
    ) -> [ProjectSuggestion] {
        let taken = Set(existing.map { ProjectAction.normalized($0.command) })
        var seen: Set<String> = []
        return detected.enumerated()
            .sorted {
                ($0.element.role, $0.element.source, $0.offset) < ($1.element.role, $1.element.source, $1.offset)
            }
            .map(\.element)
            .filter { !taken.contains($0.id) && !dismissed.contains($0.id) && seen.insert($0.id).inserted }
    }
}
