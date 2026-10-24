import Foundation
import Git
import Observation

/// How Native sets up git for new tasks: the branch prefix, whether a task gets its own worktree,
/// which ignored files a worktree gets copied, and what archiving does with the branch. Scripts that
/// run around worktrees are the task scripts' (`TaskScriptSettings`). A project can override the prefix, the
/// worktree choice and archiving for its own tasks (`ProjectOverrides`).
@Observable
final class GitSettings {
    enum BranchPrefixMode: String, CaseIterable, Identifiable, Codable {
        /// `<github-username>/`, the default.
        case gitHubUsername
        case custom
        case none

        var id: Self { self }

        var title: String {
            switch self {
            case .gitHubUsername: "GitHub login"
            case .custom: "Custom"
            case .none: "None"
            }
        }
    }

    enum NewTaskWorkspace: String, CaseIterable, Identifiable, Codable {
        /// Its own worktree under `~/.native/worktrees`, so parallel tasks never collide.
        case worktree
        /// A new branch in the project's own checkout.
        case branch

        var id: Self { self }

        var title: String {
            switch self {
            case .worktree: "Its own worktree"
            case .branch: "A branch in the project folder"
            }
        }
    }

    /// One project's own choices for its new tasks; nil follows the setting above.
    struct ProjectOverrides: Codable, Hashable {
        var newTaskWorkspace: NewTaskWorkspace?
        var branchPrefixMode: BranchPrefixMode?
        /// Used while `branchPrefixMode` is `.custom`.
        var customBranchPrefix: String?
        var deletesBranchOnArchive: Bool?
    }

    static let defaultEnvFilePatterns = [".env*"]

    var branchPrefixMode: BranchPrefixMode { didSet { save(branchPrefixMode.rawValue, for: .branchPrefixMode) } }
    var customBranchPrefix: String { didSet { save(customBranchPrefix, for: .customBranchPrefix) } }
    var newTaskWorkspace: NewTaskWorkspace { didSet { save(newTaskWorkspace.rawValue, for: .newTaskWorkspace) } }
    /// Renames a task's provisional branch after its title, until the branch is pushed.
    var renamesBranches: Bool { didSet { save(renamesBranches, for: .renamesBranches) } }
    /// Gitignore-style patterns of ignored files a new worktree gets copied from the project.
    var envFilePatterns: [String] { didSet { save(envFilePatterns, for: .envFilePatterns) } }
    /// Archiving a task deletes its branch, keeping the commits under `refs/native-archived-branches/`.
    var deletesBranchOnArchive: Bool { didSet { save(deletesBranchOnArchive, for: .deletesBranchOnArchive) } }
    /// Projects' overrides by the path of the project's main checkout.
    private(set) var projectOverrides: [String: ProjectOverrides] {
        didSet { save((try? JSONEncoder().encode(projectOverrides)) ?? Data(), for: .projectOverrides) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key: String {
        case branchPrefixMode, customBranchPrefix, newTaskWorkspace, renamesBranches, envFilePatterns
        case deletesBranchOnArchive, projectOverrides

        var name: String { "git.\(rawValue)" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        branchPrefixMode =
            defaults.string(forKey: Key.branchPrefixMode.name).flatMap(BranchPrefixMode.init) ?? .gitHubUsername
        customBranchPrefix = defaults.string(forKey: Key.customBranchPrefix.name) ?? ""
        newTaskWorkspace =
            defaults.string(forKey: Key.newTaskWorkspace.name).flatMap(NewTaskWorkspace.init) ?? .worktree
        renamesBranches = defaults.object(forKey: Key.renamesBranches.name) as? Bool ?? true
        envFilePatterns = defaults.stringArray(forKey: Key.envFilePatterns.name) ?? Self.defaultEnvFilePatterns
        deletesBranchOnArchive = defaults.bool(forKey: Key.deletesBranchOnArchive.name)
        projectOverrides =
            defaults.data(forKey: Key.projectOverrides.name).flatMap {
                try? JSONDecoder().decode([String: ProjectOverrides].self, from: $0)
            } ?? [:]
    }

    /// The prefix new branches get, e.g. `brayden/`; `gitHubLogin` is the signed-in GitHub user.
    func branchPrefix(gitHubLogin: String?) -> String {
        Self.branchPrefix(mode: branchPrefixMode, custom: customBranchPrefix, gitHubLogin: gitHubLogin)
    }

    // MARK: - Per project

    /// The project's overrides; empty when it follows every setting.
    func overrides(forProjectAt root: URL) -> ProjectOverrides {
        let key = Self.key(for: root)
        return projectOverrides.first { Self.key(for: URL(filePath: $0.key)) == key }?.value ?? ProjectOverrides()
    }

    func setOverrides(_ overrides: ProjectOverrides, forProjectAt root: URL) {
        let key = Self.key(for: root)
        var all = projectOverrides.filter { Self.key(for: URL(filePath: $0.key)) != key }
        if overrides != ProjectOverrides() { all[key] = overrides }
        projectOverrides = all
    }

    func setStartingWorkspace(_ value: NewTaskWorkspace?, project: URL?, undoManager: UndoManager? = nil) {
        let previous =
            project == nil ? newTaskWorkspace : project.flatMap { overrides(forProjectAt: $0).newTaskWorkspace }
        if let project {
            var changes = overrides(forProjectAt: project)
            changes.newTaskWorkspace = value
            setOverrides(changes, forProjectAt: project)
        } else {
            newTaskWorkspace = value ?? .worktree
        }
        undoManager?.registerUndo(withTarget: self) { settings in
            MainActor.assumeIsolated {
                settings.setStartingWorkspace(previous, project: project, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Change Workspace Default")
    }

    func newTaskWorkspace(forProjectAt root: URL) -> NewTaskWorkspace {
        overrides(forProjectAt: root).newTaskWorkspace ?? newTaskWorkspace
    }

    func branchPrefixMode(forProjectAt root: URL) -> BranchPrefixMode {
        overrides(forProjectAt: root).branchPrefixMode ?? branchPrefixMode
    }

    /// The prefix the project's new branches get.
    func branchPrefix(forProjectAt root: URL, gitHubLogin: String?) -> String {
        let overrides = overrides(forProjectAt: root)
        guard let mode = overrides.branchPrefixMode else { return branchPrefix(gitHubLogin: gitHubLogin) }
        return Self.branchPrefix(mode: mode, custom: overrides.customBranchPrefix ?? "", gitHubLogin: gitHubLogin)
    }

    func deletesBranchOnArchive(forProjectAt root: URL) -> Bool {
        overrides(forProjectAt: root).deletesBranchOnArchive ?? deletesBranchOnArchive
    }

    private static func branchPrefix(mode: BranchPrefixMode, custom: String, gitHubLogin: String?) -> String {
        switch mode {
        case .gitHubUsername: BranchNaming.normalizedPrefix(gitHubLogin ?? "")
        case .custom: BranchNaming.normalizedPrefix(custom)
        case .none: ""
        }
    }

    /// A project folder's path with symlinks resolved and no trailing slash.
    static func key(for root: URL) -> String {
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func save(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.name)
    }
}
