import Foundation
import Git
import Observation

/// How Native sets up git for new tasks, after the reference app's Git settings: the branch prefix, whether
/// a task gets its own worktree, which ignored files a worktree gets copied, each project's setup
/// script, and what archiving does with the branch.
@Observable
final class GitSettings {
    enum BranchPrefixMode: String, CaseIterable, Identifiable {
        /// `<github-username>/`, the reference app's default.
        case gitHubUsername
        case custom
        case none

        var id: Self { self }

        var title: String {
            switch self {
            case .gitHubUsername: "GitHub username"
            case .custom: "Custom"
            case .none: "None"
            }
        }
    }

    enum NewTaskWorkspace: String, CaseIterable, Identifiable {
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

    static let defaultEnvFilePatterns = [".env*"]

    var branchPrefixMode: BranchPrefixMode { didSet { save(branchPrefixMode.rawValue, for: .branchPrefixMode) } }
    var customBranchPrefix: String { didSet { save(customBranchPrefix, for: .customBranchPrefix) } }
    var newTaskWorkspace: NewTaskWorkspace { didSet { save(newTaskWorkspace.rawValue, for: .newTaskWorkspace) } }
    /// Renames a task's provisional branch after its title, until the branch is pushed.
    var renamesBranches: Bool { didSet { save(renamesBranches, for: .renamesBranches) } }
    /// Gitignore-style patterns of ignored files a new worktree gets copied from the project.
    var envFilePatterns: [String] { didSet { save(envFilePatterns, for: .envFilePatterns) } }
    /// Setup scripts by the path of the project's main checkout.
    var setupScripts: [String: String] { didSet { save(setupScripts, for: .setupScripts) } }
    /// Archiving a task deletes its branch, keeping the commits under `refs/native-archived-branches/`.
    var deletesBranchOnArchive: Bool { didSet { save(deletesBranchOnArchive, for: .deletesBranchOnArchive) } }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key: String {
        case branchPrefixMode, customBranchPrefix, newTaskWorkspace, renamesBranches, envFilePatterns
        case setupScripts, deletesBranchOnArchive

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
        setupScripts = defaults.dictionary(forKey: Key.setupScripts.name) as? [String: String] ?? [:]
        deletesBranchOnArchive = defaults.bool(forKey: Key.deletesBranchOnArchive.name)
    }

    /// The prefix new branches get, e.g. `brayden/`; `gitHubLogin` is the signed-in GitHub user.
    func branchPrefix(gitHubLogin: String?) -> String {
        switch branchPrefixMode {
        case .gitHubUsername: BranchNaming.normalizedPrefix(gitHubLogin ?? "")
        case .custom: BranchNaming.normalizedPrefix(customBranchPrefix)
        case .none: ""
        }
    }

    /// The setup script for the project whose main checkout is `root`, if it has one.
    func setupScript(forProjectAt root: URL) -> String? {
        let key = Self.key(for: root)
        // Stored keys may be spelled differently (`/tmp` and `/private/tmp`), so compare normalized.
        let script = setupScripts.first { Self.key(for: URL(filePath: $0.key)) == key }?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return script?.isEmpty == false ? script : nil
    }

    func setSetupScript(_ script: String, forProjectAt root: URL) {
        let key = Self.key(for: root)
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        var scripts = setupScripts.filter { Self.key(for: URL(filePath: $0.key)) != key }
        if !trimmed.isEmpty { scripts[key] = script }
        setupScripts = scripts
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
