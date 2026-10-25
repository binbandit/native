import ACP
import Experiments
import Foundation
import Undo

@testable import Native

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A brief's two tasks through their life: grouped while undecided, following a conversation that
/// replaces one (`/clear`), Keep archiving the current other task with one Undo, and Escape never
/// taking back a brief one of its tasks already has.
@main
@MainActor
private struct TaskPairsRegression {
    static func main() async {
        do {
            try await check()
            print("PASS: task pairs group, follow replaced conversations, keep with Undo and cancel safely")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func check() async throws {
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .composeTask)
        let defaults = PreviewUserDefaults()
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex], defaults: defaults),
            defaults: defaults, catalogURL: nil, experiments: experiments)
        _ = app.runtimes.sync()
        let project = app.projects.add(URL(filePath: "/fixture/native", directoryHint: .isDirectory))
        let codex = SessionKey(agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID("codex-1"))
        let claude = SessionKey(agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("claude-1"))
        let other = SessionKey(agent: codex.agent, id: SessionID("other"))
        for (key, minutes) in [(codex, 30.0), (other, 10.0), (claude, 1.0)] {
            app.catalog.add(
                SessionInfo(
                    sessionId: key.id, cwd: "/fixture/native-\(key.id.rawValue)", title: "Brief",
                    updatedAt: .now.addingTimeInterval(-minutes * 60)),
                for: key.agent, in: project.id)
        }
        app.taskPairs.add([codex, claude])

        // Grouped in To-line order wherever the sidebar's sort put them.
        let order = app.sessionList.map(\.id)
        let codexIndex = try require(order.firstIndex(of: codex), "Codex's task isn't listed")
        try require(order[codexIndex + 1] == claude, "The pair isn't together: \(order)")
        let pair = try require(app.openTaskPair(containing: codex), "The pair isn't open")
        try require(app.taskPairPlacement(of: codex, among: order) == .first(pair), "The first task has no heading")
        try require(app.taskPairPlacement(of: claude, among: order) == .member, "The second task isn't in the group")

        // `/clear` on Claude Code's task: the pair follows the new conversation, so Keep from Codex
        // archives the conversation working in that worktree now, never the one set aside.
        let cleared = SessionKey(agent: claude.agent, id: SessionID("claude-2"))
        app.catalog.add(
            SessionInfo(sessionId: cleared.id, cwd: "/fixture/native-claude-1", title: "Brief"), for: claude.agent,
            in: project.id)
        app.taskPairs.replace(claude, with: cleared)
        try require(app.openTaskPair(containing: cleared) != nil, "The replacement left its pair")
        try require(app.openTaskPair(containing: claude) == nil, "The set-aside conversation is still paired")

        app.selection = codex
        await app.keepTaskPairVersion(codex)
        try require(app.archivedSessions.contains(cleared), "Keep didn't archive the other task's current conversation")
        try require(!app.archivedSessions.contains(claude), "Keep archived a conversation it no longer owns")
        try require(app.keptTaskPair(containing: codex) != nil, "The pair doesn't record what was kept")
        try require(app.openTaskPair(containing: codex) == nil, "The pair is still undecided after Keep")
        let undo = try require(app.lastUndoable, "Keep offered no Undo")
        try require(undo.message.hasPrefix("Kept Codex's version"), "Undo says \(undo.message)")

        undo.undo()
        try await wait { !app.archivedSessions.contains(cleared) }
        try require(app.openTaskPair(containing: codex) != nil, "Undo didn't regroup the pair")
        try require(app.keptTaskPair(containing: codex) == nil, "Undo left the version kept")

        // Saved across launches: the pair and its replacement come back from preferences.
        let relaunched = TaskPairs(defaults: defaults)
        try require(relaunched.pair(containing: cleared)?.tasks == [codex, cleared], "The pair wasn't saved")

        // Escape before Start finished takes back both tasks, but not once one of them has opened.
        guard let agent = app.agents.first?.agent else { throw CheckFailure("No agent") }
        let first = StartingTask(project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Fixture")
        let second = StartingTask(project: project.id, agent: agent, isAgentPicked: false, workspaceLabel: "Fixture")
        app.startingTasks = [first, second]
        app.taskPairs.add([first.id, second.id])
        app.composeTask.starting = first
        try require(app.composeCanCancelStart, "A brief no task has opened can't be taken back")
        app.startingTasks.removeAll { $0 === second }
        second.openedSession = SessionKey(agent: agent.id, id: SessionID("opened"))
        try require(!app.composeCanCancelStart, "Escape could take back a brief one agent already has")

        // Both worktrees come from one commit chosen once; without one, neither starts on its own.
        let pinnedFirst = StartingTask(
            project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Fixture")
        let pinnedSecond = StartingTask(
            project: project.id, agent: agent, isAgentPicked: false, workspaceLabel: "Fixture")
        for task in [pinnedFirst, pinnedSecond] { task.workspaceChoice = .newWorktree }
        app.startingTasks = [pinnedFirst, pinnedSecond]
        app.taskPairs.add([pinnedFirst.id, pinnedSecond.id])
        try require(
            !(await app.pinSharedWorktreeStart(for: [pinnedFirst, pinnedSecond])), "Started without a shared commit")
        try require(
            pinnedFirst.failure != nil && pinnedSecond.failure != nil, "A task was left to start on its own")
        let workspaces = PinningWorkspaces()
        app.taskWorkspaces = workspaces
        try require(await app.pinSharedWorktreeStart(for: [pinnedFirst, pinnedSecond]), "Couldn't pin a start")
        let shared = TaskWorkspaceChoice.newWorktreeFrom(commit: "abc123", branch: "main", notice: nil)
        try require(
            pinnedFirst.workspaceChoice == shared && pinnedSecond.workspaceChoice == shared,
            "The two tasks start from different commits")
        try require(workspaces.lookups == 1, "The start was chosen \(workspaces.lookups) times")
        try require(
            app.taskPairs.pair(containing: pinnedFirst.id)?.start == "abc123", "The pair didn't keep its start")

        // Two Retries looking up at once, answered with different commits: the first answer stands.
        let racingFirst = StartingTask(
            project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Fixture")
        let racingSecond = StartingTask(
            project: project.id, agent: agent, isAgentPicked: false, workspaceLabel: "Fixture")
        for task in [racingFirst, racingSecond] { task.workspaceChoice = .newWorktree }
        app.startingTasks = [racingFirst, racingSecond]
        app.taskPairs.add([racingFirst.id, racingSecond.id])
        workspaces.holdsLookups = true
        let earlier = Task { await app.pinSharedWorktreeStart(for: [racingFirst, racingSecond]) }
        let later = Task { await app.pinSharedWorktreeStart(for: [racingSecond, racingFirst]) }
        try await wait { workspaces.pending.count == 2 }
        workspaces.answer(0, with: "aaa111")
        _ = await earlier.value
        workspaces.answer(0, with: "bbb222")
        _ = await later.value
        let racedStart = TaskWorkspaceChoice.newWorktreeFrom(commit: "aaa111", branch: "main", notice: nil)
        try require(
            racingFirst.workspaceChoice == racedStart && racingSecond.workspaceChoice == racedStart,
            "A later lookup moved a task to another commit")
        try require(
            app.taskPairs.pair(containing: racingFirst.id)?.start == "aaa111", "A later lookup moved the pair's base")
    }

    @discardableResult
    static func require<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else { throw CheckFailure(message) }
        return value
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message) }
    }

    static func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CheckFailure("Timed out")
    }
}

/// Answers where new worktrees start, counting the lookups; nothing else is used here.
@MainActor
private final class PinningWorkspaces: TaskWorkspaceProvider {
    var lookups = 0
    /// Held lookups wait for `answer`, oldest first.
    var holdsLookups = false
    var pending: [CheckedContinuation<String, Never>] = []

    func answer(_ index: Int, with commit: String) {
        pending.remove(at: index).resume(returning: commit)
    }

    func newWorktreeStart(in project: Project) async throws -> TaskWorkspaceChoice? {
        lookups += 1
        let commit = holdsLookups ? await withCheckedContinuation { pending.append($0) } : "abc123"
        return .newWorktreeFrom(commit: commit, branch: "main", notice: nil)
    }
    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption] { [] }
    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL { project.url }
    func prepareWorkspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> TaskWorkspacePreparation
    {
        .init(folder: project.url, createdForTask: false)
    }
    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool { false }
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL { project.url }
    func newTaskWorkspaceLabel(in project: Project) -> String { "Fixture" }
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? { nil }
    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        false
    }
    func archivedWorkspaceFolders(of project: Project) async -> [URL] { [] }
    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] { [:] }
    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {}
    func deleteWorkspace(at folder: URL, in project: Project) async throws {}
    func deleteWorkspaces(of project: Project) async throws {}
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {}
    func taskFolders(of project: Project) async -> [URL] { [] }
}
