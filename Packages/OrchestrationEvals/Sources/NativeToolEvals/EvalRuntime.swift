import Foundation
import NativeOrchestration

/// Synthetic state only. No agent subprocess, host store, checkout, network or user data is accessed.
public actor EvalRuntime: TaskRuntime {
    public nonisolated let caller: OrchestrationCaller
    private let root = TaskSessionRef(agent: "claude-code", id: "fixture-root")
    private let current: TaskSessionRef
    private let agentIDs: [String]
    private var records: [OrchestrationTask] = []
    private var snapshots: [TaskSessionRef: TaskSnapshot] = [:]

    public init(_ test: ToolUseCase) {
        agentIDs = test.agents
        current = test.isChild ? TaskSessionRef(agent: "claude-code", id: "fixture-child") : root
        caller = OrchestrationCaller(clientID: UUID(), agent: "claude-code", cwd: URL(filePath: "/fixture"))
        snapshots[root] = TaskSnapshot(status: .running)
        snapshots[current] = TaskSnapshot(status: .running)
        if test.isChild {
            records.append(
                OrchestrationTask(
                    id: "task-self", session: current, agentName: "Claude Code", title: "Current check", parent: root,
                    parentAgentName: "Claude Code"))
        }
        for seed in test.seeds {
            let session = TaskSessionRef(agent: "review-agent", id: seed.id)
            records.append(
                OrchestrationTask(
                    id: seed.id, session: session, agentName: "Fixture reviewer", title: seed.title,
                    parent: root, parentAgentName: "Claude Code"))
            snapshots[session] = TaskSnapshot(
                status: seed.status, reply: seed.reply,
                detail: seed.status == .needsApproval ? "read Cache.swift" : nil)
        }
    }

    public var isReady: Bool { true }
    public func taskAgents() -> [TaskAgent] {
        agentIDs.map { TaskAgent(id: $0, name: $0 == "claude-code" ? "Claude Code" : "Fixture reviewer") }
    }
    public func caller(of clientID: UUID) -> OrchestrationCaller? { clientID == caller.clientID ? caller : nil }
    public func session(of clientID: UUID) -> TaskSessionRef? { clientID == caller.clientID ? current : nil }
    public func tasks() -> [OrchestrationTask] { records }
    public func startTask(_ request: TaskRequest) -> OrchestrationTask {
        let session = TaskSessionRef(agent: request.agent.id, id: request.id)
        let task = OrchestrationTask(
            id: request.id, session: session, agentName: request.agent.name, title: request.title,
            parent: request.parent, parentAgentName: request.parentAgentName)
        records.append(task)
        snapshots[session] = TaskSnapshot(status: .running)
        return task
    }
    public func openTask(_ task: OrchestrationTask) {}
    public func snapshot(of session: TaskSessionRef) -> TaskSnapshot? { snapshots[session] }
    public func settle(_ session: TaskSessionRef, timeout: Duration) {
        if snapshots[session]?.status == .running {
            snapshots[session] = TaskSnapshot(status: .idle, reply: "Cache expiry needs a regression test.")
        }
    }
    public func deliver(_ message: TaskMessage) -> TaskMessage.Delivery {
        let running = snapshots[message.recipient]?.status == .running
        snapshots[message.recipient] = TaskSnapshot(status: .running)
        return running ? .steered : .prompted
    }
    public func cancelTask(_ session: TaskSessionRef) { snapshots[session] = TaskSnapshot(status: .cancelled) }
    public func disabledSkills(of clientID: UUID) -> Set<String> { [] }
}
