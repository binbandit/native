import Foundation
import NativePolicy
import Observation
import TaskScripts

/// The task scripts set up on this Mac: global ones, each project's own, how they combine, timeouts,
/// and which projects' repository scripts may run. Kept as one JSON value under
/// `taskScripts.configuration`; the organization's policy decides which kinds may run at all.
@Observable
final class TaskScriptSettings {
    private(set) var configuration: TaskScriptConfiguration {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let policy: () -> NativePolicy

    private static let configurationKey = "taskScripts.configuration"
    /// Where each project's setup script lived before there were other events.
    private static let legacySetupScriptsKey = "git.setupScripts"

    init(defaults: UserDefaults = .standard, policy: @escaping () -> NativePolicy = { PolicyCenter.shared.policy }) {
        self.defaults = defaults
        self.policy = policy
        if let data = defaults.data(forKey: Self.configurationKey),
            let stored = try? JSONDecoder().decode(TaskScriptConfiguration.self, from: data)
        {
            configuration = stored
        } else {
            configuration = Self.migrated(from: defaults)
            save()
        }
    }

    /// What the organization lets run.
    var permissions: TaskScriptPermissions {
        let scripts = policy().taskScripts
        return TaskScriptPermissions(
            userScripts: scripts.userScriptsEnabled, repositoryScripts: scripts.repositoryScriptsEnabled)
    }

    // MARK: - Global

    func script(for event: TaskScriptEvent) -> String {
        configuration.global[event] ?? ""
    }

    func setScript(_ text: String, for event: TaskScriptEvent) {
        configuration.global[event] = text.isBlank ? nil : text
    }

    func timeout(for event: TaskScriptEvent) -> Duration {
        configuration.timeout(for: event)
    }

    func setTimeout(_ timeout: Duration, for event: TaskScriptEvent) {
        configuration.timeouts[event] = timeout == event.defaultTimeout ? nil : timeout
    }

    // MARK: - Projects

    /// The settings of the project whose main checkout is at `root`.
    func project(at root: URL) -> ProjectTaskScripts {
        configuration.project(at: root)
    }

    /// The projects with scripts or choices of their own, by main checkout.
    var customizedProjects: [URL] {
        configuration.projects.keys.sorted().map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    func setProjectScript(_ text: String, for event: TaskScriptEvent, at root: URL) {
        configuration.updateProject(at: root) { $0.scripts[event] = text.isBlank ? nil : text }
    }

    func setCombination(_ combination: ProjectTaskScripts.Combination, for event: TaskScriptEvent, at root: URL) {
        configuration.updateProject(at: root) {
            $0.combinations[event] = combination == .afterGlobal ? nil : combination
        }
    }

    /// Whether the scripts the project's repository commits may run here: the user allowed them, and
    /// the organization doesn't turn repository scripts off.
    func allowsRepositoryScripts(forProjectAt root: URL) -> Bool {
        permissions.repositoryScripts && project(at: root).allowsRepositoryScripts
    }

    func setAllowsRepositoryScripts(_ allowed: Bool, forProjectAt root: URL) {
        configuration.updateProject(at: root) { $0.allowsRepositoryScripts = allowed }
    }

    /// The scripts the repository at `root` commits in `.native/`, by event, read now.
    func repositoryScripts(at root: URL) -> [TaskScriptEvent: String] {
        TaskScriptRepositoryFiles.read(at: root)
    }

    /// What runs for `event` in the project at `project` (nil for a folder outside any project).
    func plan(for event: TaskScriptEvent, project: URL?) -> TaskScriptPlan {
        configuration.plan(
            for: event, project: project, repository: project.map(repositoryScripts(at:)) ?? [:],
            permissions: permissions)
    }

    // MARK: - Storage

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.configurationKey)
    }

    /// The setup scripts Native kept per project before, as those projects' own setup scripts. The
    /// old value stays where it was, so an older Native still finds it.
    private static func migrated(from defaults: UserDefaults) -> TaskScriptConfiguration {
        var configuration = TaskScriptConfiguration()
        let legacy = defaults.dictionary(forKey: legacySetupScriptsKey) as? [String: String] ?? [:]
        for (path, script) in legacy where !script.isBlank {
            configuration.updateProject(at: URL(filePath: path, directoryHint: .isDirectory)) {
                $0.scripts[.setup] = script
            }
        }
        return configuration
    }
}

extension String {
    fileprivate var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
