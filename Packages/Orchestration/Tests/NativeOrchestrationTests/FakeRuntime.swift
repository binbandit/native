import Foundation
import MCP

@testable import NativeOrchestration

/// Sessions in memory: each one's snapshot is what the test says, and every request is recorded.
actor FakeRuntime: TaskRuntime {
    var ready = true
    var scopes: [UUID: CoordinatorScope] = [:]
    func setScope(_ scope: CoordinatorScope, for caller: OrchestrationCaller) { scopes[caller.clientID] = scope }
    func coordinatorScope(of clientID: UUID) -> CoordinatorScope? { scopes[clientID] }
    func recentTranscript(of session: TaskSessionRef) -> String? { "Recent visible transcript" }
    var agents = [TaskAgent(id: "claude", name: "Claude Code"), TaskAgent(id: "codex", name: "Codex")]
    /// Open sessions by Native's id, with their lasting name and agent.
    var open: [UUID: (session: TaskSessionRef, cwd: URL)] = [:]
    var snapshots: [TaskSessionRef: TaskSnapshot] = [:]
    private(set) var records: [OrchestrationTask] = []
    private(set) var started: [TaskRequest] = []
    private(set) var reopened: [String] = []
    private(set) var delivered: [TaskMessage] = []
    private(set) var cancelled: [TaskSessionRef] = []

    var isReady: Bool { ready }

    func setReady(_ ready: Bool) {
        self.ready = ready
    }

    /// A session of `agent` the user started, open now.
    @discardableResult
    func openSession(agent: String, id: String = UUID().uuidString) -> OrchestrationCaller {
        let clientID = UUID()
        let cwd = URL(filePath: "/projects/app", directoryHint: .isDirectory)
        open[clientID] = (TaskSessionRef(agent: agent, id: id), cwd)
        snapshots[TaskSessionRef(agent: agent, id: id)] = TaskSnapshot(status: .idle)
        return OrchestrationCaller(clientID: clientID, agent: agent, cwd: cwd)
    }

    /// The caller a task's own session is.
    func caller(ofTask task: OrchestrationTask) -> OrchestrationCaller? {
        open.first { $0.value.session == task.session }.map {
            OrchestrationCaller(clientID: $0.key, agent: task.session.agent, cwd: $0.value.cwd)
        }
    }

    func close(_ session: TaskSessionRef) {
        open = open.filter { $0.value.session != session }
        snapshots[session] = nil
    }

    func set(_ snapshot: TaskSnapshot, for session: TaskSessionRef) {
        snapshots[session] = snapshot
    }

    func taskAgents() -> [TaskAgent] { agents }

    func caller(of clientID: UUID) -> OrchestrationCaller? {
        open[clientID].map { OrchestrationCaller(clientID: clientID, agent: $0.session.agent, cwd: $0.cwd) }
    }

    func session(of clientID: UUID) -> TaskSessionRef? {
        open[clientID]?.session
    }

    func tasks() -> [OrchestrationTask] { records }

    func startTask(_ request: TaskRequest) throws -> OrchestrationTask {
        started.append(request)
        let session = TaskSessionRef(agent: request.agent.id, id: "s-\(request.id)")
        open[UUID()] = (session, URL(filePath: "/projects/app", directoryHint: .isDirectory))
        snapshots[session] = TaskSnapshot(status: .running)
        let task = OrchestrationTask(
            id: request.id, session: session, agentName: request.agent.name, title: request.title,
            parent: request.parent, parentAgentName: request.parentAgentName)
        records.append(task)
        return task
    }

    func openTask(_ task: OrchestrationTask) {
        reopened.append(task.id)
        open[UUID()] = (task.session, URL(filePath: "/projects/app", directoryHint: .isDirectory))
        snapshots[task.session] = TaskSnapshot(status: .idle, reply: "from before")
    }

    func snapshot(of session: TaskSessionRef) -> TaskSnapshot? {
        snapshots[session]
    }

    func settle(_ session: TaskSessionRef, timeout: Duration) {}

    func deliver(_ message: TaskMessage) -> TaskMessage.Delivery {
        delivered.append(message)
        return .prompted
    }

    func cancelTask(_ session: TaskSessionRef) {
        cancelled.append(session)
        snapshots[session] = TaskSnapshot(status: .cancelled)
    }

    func disabledSkills(of clientID: UUID) -> Set<String> { ["build-a-native-plugin"] }
}
