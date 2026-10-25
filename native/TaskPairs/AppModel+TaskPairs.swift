import ACP
import Experiments
import Foundation
import TaskList
import Undo

// A brief sent to two agents (Compose): the two tasks stay one group until the user keeps one.
// Everything here is behind the Compose Task switch, which is the only way a pair is made.
extension AppModel {
    /// Pairs are made and shown only with Compose on.
    var offersTaskPairs: Bool { experiments.value(of: .composeTask) }

    /// The pair `key` belongs to while it's still undecided: neither kept, archived nor deleted.
    func openTaskPair(containing key: SessionKey) -> TaskPair? {
        guard offersTaskPairs, let pair = taskPairs.pair(containing: key), pair.kept == nil,
            pair.tasks.allSatisfy({ task in
                !archivedSessions.contains(task) && !deletedSessions.contains(task) && pendingDeletions[task] == nil
            })
        else { return nil }
        return pair
    }

    /// The pair `key` was kept from, for the record under its changes.
    func keptTaskPair(containing key: SessionKey) -> TaskPair? {
        guard offersTaskPairs, let pair = taskPairs.pair(containing: key), pair.kept == key else { return nil }
        return pair
    }

    /// The pair on screen in Compare, when `key` is one of its tasks.
    func comparedTaskPair(for key: SessionKey) -> TaskPair? {
        guard let id = taskPairs.comparing, let pair = openTaskPair(containing: key), pair.id == id else { return nil }
        return pair
    }

    /// Whether a task of a pair has finished for now: not starting, working or waiting on the user.
    /// Versions are compared and kept only when both are.
    func isTaskPairMemberSettled(_ key: SessionKey) -> Bool {
        guard !key.isStartingPlaceholder else { return false }
        return switch TaskFacts.Activity(session(key)) {
        case .running, .needsYou: false
        case .idle, .done, .failed: true
        }
    }

    func isTaskPairSettled(_ pair: TaskPair) -> Bool {
        pair.tasks.allSatisfy(isTaskPairMemberSettled)
    }

    /// The agent's name, which is how a pair's tasks are told apart.
    func taskPairAgentName(_ key: SessionKey) -> String {
        session(key)?.agentName ?? startingTask(key)?.agent.displayName ?? plugins.agent(key.agent)?.displayName
            ?? key.agent.rawValue
    }

    /// The sidebar's lists with each open pair's tasks together.
    func groupTaskPairs(_ lists: [[SessionSummary]]) -> [[SessionSummary]] {
        guard offersTaskPairs, !taskPairs.all.isEmpty else { return lists }
        let open = taskPairs.all.filter { pair in pair.tasks.first.flatMap(openTaskPair(containing:)) != nil }
        guard !open.isEmpty else { return lists }
        let lookup = Dictionary(lists.flatMap { $0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return TaskPairGrouping.grouped(lists.map { $0.map(\.id) }, pairs: open.map(\.tasks))
            .map { $0.compactMap { lookup[$0] } }
    }

    /// Where a row sits in its pair's group, when both of the pair's tasks are in `visible`.
    func taskPairPlacement(of key: SessionKey, among visible: [SessionKey]) -> TaskPairPlacement? {
        guard let pair = openTaskPair(containing: key), pair.tasks.allSatisfy(visible.contains) else { return nil }
        return pair.tasks.first == key ? .first(pair) : .member
    }

    func compareTaskPair(containing key: SessionKey) {
        guard let pair = openTaskPair(containing: key), isTaskPairSettled(pair) else { return }
        taskPairs.comparing = pair.id
    }

    func closeTaskPairComparison() {
        taskPairs.comparing = nil
    }

    /// Keeps `key`'s version: the pair becomes that one task, and the other is archived, which puts
    /// its worktree away after saving its branch and uncommitted work. One Undo (the toast or ⌘Z)
    /// brings the other back, worktree and all, and groups the two again.
    func keepTaskPairVersion(_ key: SessionKey, undoManager: UndoManager? = nil) async {
        guard let pair = openTaskPair(containing: key), isTaskPairSettled(pair), let other = pair.other(than: key),
            let listed = catalog.lookup(other)
        else { return }
        let kept = taskPairAgentName(key)
        let archived = taskPairAgentName(other)
        let title = titleOfSession(other)
        taskPairs.comparing = nil
        taskPairs.setKept(key, in: pair.id)
        selection = key
        _ = taskActionRoute(for: other)
        archivedSessions.set(other, archived: true)
        let action = offerUndo(
            "Kept \(kept)'s version and archived \(archived)'s.", name: "Keep Version", undoManager: undoManager
        ) { model in
            model.taskPairs.setKept(nil, in: pair.id)
            model.undoArchive([other], selecting: nil)
        } redo: { model in
            model.taskPairs.setKept(key, in: pair.id)
            model.archiveAgain([other])
        }
        let detail = await putAwayWorkspace(of: other, titled: title, in: listed.project)
        guard action.canUndo else { return }
        action.message += detail
    }
}

/// A row's place in its pair's sidebar group: the first task carries the group's heading.
enum TaskPairPlacement: Equatable {
    case first(TaskPair)
    case member
}
