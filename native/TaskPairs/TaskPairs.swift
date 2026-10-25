import ACP
import Foundation
import Observation

/// One brief sent to two agents: two tasks, each in its own worktree, kept together in the sidebar
/// until the user keeps one. The other is archived then, its worktree put away with a checkpoint.
struct TaskPair: Codable, Hashable, Identifiable {
    let id: UUID
    /// In the order the To line named them. A starting task's placeholder key until it opens.
    var tasks: [SessionKey]
    /// The task the user kept; the pair is one task again from then on.
    var kept: SessionKey?
    /// The commit both worktrees were made from, to compare their work from.
    var start: String?

    func other(than key: SessionKey) -> SessionKey? {
        tasks.first { $0 != key }
    }
}

/// The pairs Compose started, saved across launches.
@Observable
final class TaskPairs {
    private(set) var all: [TaskPair]
    /// The pair whose versions are side by side on screen, if any. Not saved.
    var comparing: TaskPair.ID?

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "taskPairs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([TaskPair].self, from: $0) }
        // A task still starting when Native quit never opened, so its pair has nothing to keep.
        all = (saved ?? []).filter { !$0.tasks.contains(where: \.isStartingPlaceholder) }
    }

    func pair(containing key: SessionKey) -> TaskPair? {
        all.first { $0.tasks.contains(key) }
    }

    func pair(_ id: TaskPair.ID) -> TaskPair? {
        all.first { $0.id == id }
    }

    func add(_ tasks: [SessionKey]) {
        all.append(TaskPair(id: UUID(), tasks: tasks))
        save()
    }

    /// A task's conversation was replaced (it opened from starting, `/clear`, Change Agent, a new
    /// workspace): the pair follows the task, not the conversation it left.
    func replace(_ old: SessionKey, with new: SessionKey) {
        guard let index = all.firstIndex(where: { $0.tasks.contains(old) }) else { return }
        all[index].tasks = all[index].tasks.map { $0 == old ? new : $0 }
        if all[index].kept == old { all[index].kept = new }
        save()
    }

    func setStart(_ commit: String, forPairContaining key: SessionKey) {
        guard let index = all.firstIndex(where: { $0.tasks.contains(key) }) else { return }
        all[index].start = commit
        save()
    }

    /// A task left before it opened (discarded while starting): the other one is a task of its own.
    func forget(_ key: SessionKey) {
        all.removeAll { $0.tasks.contains(key) }
        save()
    }

    func setKept(_ key: SessionKey?, in id: TaskPair.ID) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].kept = key
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.key) }
    }
}

extension SessionKey {
    /// A `StartingTask`'s stand-in key, before its session exists.
    var isStartingPlaceholder: Bool { id.rawValue.hasPrefix("native-starting-") }
}
