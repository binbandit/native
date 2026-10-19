import Foundation
import Observation
import ProjectActions

/// Every project's actions: the user's own (in preferences, by the project's checkout), the ones
/// its repo shares in `.native/actions.json`, and the suggestions Native found in its files, minus
/// those the user dismissed. Repo files and suggestions are read off the main thread, from the
/// project's own checkout (never a task's worktree, so a branch can't supply them), when a view
/// that shows them appears.
@MainActor
@Observable
final class ProjectActionStore {
    /// The user's actions, by project key (`key(for:)`), in their order.
    private(set) var own: [String: [ProjectAction]] {
        didSet {
            save(own, as: .actions)
            actionsChanged()
        }
    }
    /// Dismissed suggestions' ids (their commands), by project key.
    private(set) var dismissed: [String: Set<String>] {
        didSet { save(dismissed.mapValues { $0.sorted() }, as: .dismissed) }
    }
    /// The action each project ran last, for Run Last.
    private(set) var lastRun: [String: ProjectAction.ID] {
        didSet { save(lastRun, as: .lastRun) }
    }
    /// A project whose settings should open the new-action editor when they appear, for Add
    /// Action… in a menu.
    var requestedNewAction: Project.ID?
    /// What the project's files offer, by project key, once read.
    private(set) var scans: [String: ProjectActionScan] = [:] {
        didSet { actionsChanged() }
    }

    @ObservationIgnored private var scanning: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    /// Whether the organization lets repo files supply commands (shared with the repo's event
    /// scripts); false hides the repo's actions.
    @ObservationIgnored var allowsRepositoryActions: () -> Bool = { true }
    /// Told when any project's actions change, so each action's command can be registered.
    @ObservationIgnored var actionsChanged: () -> Void = {}

    private enum Key: String {
        case actions, dismissed, lastRun

        var name: String { "projectActions.\(rawValue)" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        own = Self.load([String: [ProjectAction]].self, from: defaults, key: .actions) ?? [:]
        dismissed = (Self.load([String: [String]].self, from: defaults, key: .dismissed) ?? [:]).mapValues(Set.init)
        lastRun = Self.load([String: ProjectAction.ID].self, from: defaults, key: .lastRun) ?? [:]
    }

    /// A project folder's path with symlinks resolved and no trailing slash, as the Git and repo
    /// script settings key projects.
    static func key(for root: URL) -> String {
        GitSettings.key(for: root)
    }

    // MARK: Reading

    /// The project's actions and suggestions as they stand; `refresh(_:)` reads its files.
    func list(for project: Project) -> ProjectActionList {
        let key = Self.key(for: project.url)
        let scan = scans[key]
        let repository = allowsRepositoryActions() ? scan?.repository ?? .none : .none
        let yours = own[key] ?? []
        let fromRepository = repository.actions
        return ProjectActionList(
            yours: yours,
            fromRepository: fromRepository,
            repositoryFile: repository,
            isRepositoryOff: !allowsRepositoryActions(),
            suggestions: ProjectSuggestion.visible(
                scan?.suggestions ?? [], existing: yours + fromRepository, dismissed: dismissed[key] ?? []),
            hasScanned: scan != nil
        )
    }

    /// Every action name any project has, for the commands that run them ("Run: Test").
    var actionNames: [String] {
        let repository = allowsRepositoryActions() ? scans.values.flatMap(\.repository.actions) : []
        return (own.values.flatMap(\.self) + repository).map(\.name)
    }

    /// The action `id` in the project, the user's or the repo's.
    func action(_ id: ProjectAction.ID, in project: Project) -> ProjectAction? {
        list(for: project).all.first { $0.id == id }
    }

    func lastRunAction(in project: Project) -> ProjectAction? {
        lastRun[Self.key(for: project.url)].flatMap { action($0, in: project) }
    }

    /// Reads the project's repo file and looks for suggestions again, off the main thread. A read
    /// already under way is shared.
    func refresh(_ project: Project) {
        let key = Self.key(for: project.url)
        guard scanning[key] == nil else { return }
        let root = project.url
        scanning[key] = Task {
            let scan = await Self.scan(root)
            scans[key] = scan
            scanning[key] = nil
        }
    }

    @concurrent
    private static func scan(_ root: URL) async -> ProjectActionScan {
        ProjectActionScan(
            repository: ProjectActionFile.read(in: root), suggestions: ProjectDetector.suggestions(in: root))
    }

    // MARK: Changing

    func add(_ action: ProjectAction, to project: Project) {
        own[Self.key(for: project.url), default: []].append(action)
    }

    /// Adds a suggestion as the user's own action, named so it doesn't clash; returns it.
    @discardableResult
    func add(_ suggestion: ProjectSuggestion, to project: Project) -> ProjectAction {
        let action = suggestion.action(among: list(for: project).all)
        add(action, to: project)
        return action
    }

    func update(_ action: ProjectAction, in project: Project) {
        let key = Self.key(for: project.url)
        guard let index = own[key]?.firstIndex(where: { $0.id == action.id }) else { return }
        own[key]?[index] = action
    }

    /// Removes one of the user's actions, returning it and where it was, for undo.
    @discardableResult
    func remove(_ id: ProjectAction.ID, from project: Project) -> (action: ProjectAction, index: Int)? {
        let key = Self.key(for: project.url)
        guard let index = own[key]?.firstIndex(where: { $0.id == id }), let action = own[key]?.remove(at: index)
        else { return nil }
        return (action, index)
    }

    /// Puts a removed action back where it was.
    func restore(_ action: ProjectAction, at index: Int, in project: Project) {
        let key = Self.key(for: project.url)
        var actions = own[key] ?? []
        guard !actions.contains(where: { $0.id == action.id }) else { return }
        actions.insert(action, at: min(index, actions.count))
        own[key] = actions
    }

    /// Moves one of the user's actions up or down by `offset` places.
    func move(_ id: ProjectAction.ID, by offset: Int, in project: Project) {
        let key = Self.key(for: project.url)
        guard var actions = own[key], let index = actions.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard actions.indices.contains(destination) else { return }
        actions.swapAt(index, destination)
        own[key] = actions
    }

    func dismiss(_ suggestion: ProjectSuggestion, in project: Project) {
        dismissed[Self.key(for: project.url), default: []].insert(suggestion.id)
    }

    func undismiss(_ suggestion: ProjectSuggestion, in project: Project) {
        dismissed[Self.key(for: project.url)]?.remove(suggestion.id)
    }

    /// Brings back every dismissed suggestion.
    func undismissAll(in project: Project) {
        dismissed[Self.key(for: project.url)] = nil
    }

    func dismissedCount(in project: Project) -> Int {
        dismissed[Self.key(for: project.url)]?.count ?? 0
    }

    func requestNewAction(in project: Project) {
        requestedNewAction = project.id
    }

    func recordRun(_ id: ProjectAction.ID, in project: Project) {
        lastRun[Self.key(for: project.url)] = id
    }

    // MARK: Preferences

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: Key) -> Value? {
        defaults.data(forKey: key.name).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save(_ value: some Encodable, as key: Key) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key.name)
        }
    }
}

/// What a project's files offer: the repo's shared actions and the detected suggestions. Made off
/// the main thread.
nonisolated struct ProjectActionScan: Sendable {
    let repository: ProjectActionFile.Contents
    let suggestions: [ProjectSuggestion]
}

/// A project's actions as the menus and the settings page show them.
struct ProjectActionList {
    /// The user's own, in their order.
    let yours: [ProjectAction]
    /// The repo's, in the file's order.
    let fromRepository: [ProjectAction]
    /// How reading the repo file went, for the settings page to explain.
    let repositoryFile: ProjectActionFile.Contents
    /// The organization turned off commands from repo files.
    let isRepositoryOff: Bool
    /// Suggestions not added or dismissed, best first.
    let suggestions: [ProjectSuggestion]
    /// Whether the project's files have been read yet.
    let hasScanned: Bool

    var all: [ProjectAction] { yours + fromRepository }
}
