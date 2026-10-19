import Foundation

/// The scripts the user set up in Native: global ones, each project's own and how they combine with
/// the global ones, timeouts, and which projects' repository scripts may run on this Mac. Stored as
/// JSON in Native's settings; events this version doesn't know are dropped when it's read.
public struct TaskScriptConfiguration: Hashable, Sendable {
    /// Scripts every project runs.
    public var global: [TaskScriptEvent: String] = [:]
    /// How long an event's scripts may run, where the user changed it from the event's default.
    public var timeouts: [TaskScriptEvent: Duration] = [:]
    /// Each project's own settings, by `TaskScriptConfiguration.key(for:)` of its main checkout.
    public var projects: [String: ProjectTaskScripts] = [:]

    public init(
        global: [TaskScriptEvent: String] = [:], timeouts: [TaskScriptEvent: Duration] = [:],
        projects: [String: ProjectTaskScripts] = [:]
    ) {
        self.global = global
        self.timeouts = timeouts
        self.projects = projects
    }

    public func timeout(for event: TaskScriptEvent) -> Duration {
        timeouts[event] ?? event.defaultTimeout
    }

    /// The settings of the project whose main checkout is at `root`, empty for a project without any.
    public func project(at root: URL) -> ProjectTaskScripts {
        projects[Self.key(for: root)] ?? ProjectTaskScripts()
    }

    /// Changes the settings of the project at `root`, forgetting them once they're all defaults.
    public mutating func updateProject(at root: URL, _ change: (inout ProjectTaskScripts) -> Void) {
        let key = Self.key(for: root)
        var project = projects[key] ?? ProjectTaskScripts()
        change(&project)
        projects[key] = project.isEmpty ? nil : project
    }

    /// A project folder's path with symlinks resolved and no trailing slash, so `/tmp/app` and
    /// `/private/tmp/app/` are the same project.
    public static func key(for root: URL) -> String {
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// One project's scripts in Native's settings.
public struct ProjectTaskScripts: Hashable, Sendable {
    /// How a project's script for an event goes with the global one.
    public enum Combination: String, Hashable, Sendable, CaseIterable {
        /// The global script runs, then the project's.
        case afterGlobal
        /// Only the project's script runs. Without one, nothing runs for the event in the project.
        case insteadOfGlobal
    }

    /// Scripts kept on this Mac, for events the repository has no script for.
    public var scripts: [TaskScriptEvent: String] = [:]
    /// Events whose script doesn't go after the global one.
    public var combinations: [TaskScriptEvent: Combination] = [:]
    /// Whether the repository's own scripts (`.native/<event>.sh`) may run. Off until the user
    /// allows them, since they come from whoever commits to the repository.
    public var allowsRepositoryScripts = false

    public init(
        scripts: [TaskScriptEvent: String] = [:], combinations: [TaskScriptEvent: Combination] = [:],
        allowsRepositoryScripts: Bool = false
    ) {
        self.scripts = scripts
        self.combinations = combinations
        self.allowsRepositoryScripts = allowsRepositoryScripts
    }

    public func combination(for event: TaskScriptEvent) -> Combination {
        combinations[event] ?? .afterGlobal
    }

    var isEmpty: Bool {
        scripts.isEmpty && combinations.isEmpty && !allowsRepositoryScripts
    }
}

// MARK: - Storage

extension TaskScriptConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case global, timeouts, projects
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        global = try container.decodeIfPresent([String: String].self, forKey: .global)?.byEvent ?? [:]
        timeouts =
            try container.decodeIfPresent([String: Int].self, forKey: .timeouts)?.byEvent.mapValues { .seconds($0) }
            ?? [:]
        projects = try container.decodeIfPresent([String: ProjectTaskScripts].self, forKey: .projects) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(global.byName, forKey: .global)
        try container.encode(timeouts.mapValues { Int($0.components.seconds) }.byName, forKey: .timeouts)
        try container.encode(projects, forKey: .projects)
    }
}

extension ProjectTaskScripts: Codable {
    private enum CodingKeys: String, CodingKey {
        case scripts, combinations, allowsRepositoryScripts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scripts = try container.decodeIfPresent([String: String].self, forKey: .scripts)?.byEvent ?? [:]
        combinations =
            try container.decodeIfPresent([String: String].self, forKey: .combinations)?.byEvent
            .compactMapValues(Combination.init(rawValue:)) ?? [:]
        allowsRepositoryScripts = try container.decodeIfPresent(Bool.self, forKey: .allowsRepositoryScripts) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scripts.byName, forKey: .scripts)
        try container.encode(combinations.mapValues(\.rawValue).byName, forKey: .combinations)
        try container.encode(allowsRepositoryScripts, forKey: .allowsRepositoryScripts)
    }
}

extension Dictionary where Key == String {
    /// Keyed by event, leaving out names this version doesn't know.
    fileprivate var byEvent: [TaskScriptEvent: Value] {
        reduce(into: [:]) { result, entry in
            if let event = TaskScriptEvent(rawValue: entry.key) { result[event] = entry.value }
        }
    }
}

extension Dictionary where Key == TaskScriptEvent {
    fileprivate var byName: [String: Value] {
        reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
    }
}
