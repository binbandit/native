import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration
import Testing

@testable import NativeHost

@Suite(.serialized)
@HostActor
struct HostDelegationStopTests {
    @Test(arguments: [false, true])
    func stopClaimsOnlySubtreeTurnsAcrossRestart(legacy: Bool) throws {
        let rig = try HostStopCommandRig()
        defer { rig.cleanup() }
        func session(_ name: String) throws -> HostSession {
            let record = StoredSession(
                id: HostSessionID(), agentID: "fake", agentSessionID: SessionID(name),
                cwd: rig.harness.root.path, parentID: nil, origin: .user)
            try rig.core.store.insertSession(record)
            let session = HostSession(
                record: record, agentName: "Fake", phase: .prompting, needsLoad: false, mcpServers: [])
            let turn = UnfinishedTurn(sessionID: record.id, prompt: OutgoingPrompt(text: "work"), kind: .prompt)
            try rig.core.store.beginTurn(turn)
            session.turn = turn
            rig.core.sessions[record.id] = session
            return session
        }
        let parent = try session("parent")
        let child = try session("child")
        let unrelated = try session("unrelated")
        let parentTurn = try #require(parent.turn)
        let childTurn = try #require(child.turn)
        let unrelatedTurn = try #require(unrelated.turn)
        let parentRef = TaskSessionRef(agent: "fake", id: "parent")
        let childRef = TaskSessionRef(agent: "fake", id: "child")
        let task = OrchestrationTask(
            id: "task", session: childRef, agentName: "Fake", title: "work", parent: parentRef,
            parentAgentName: "Fake")
        try rig.core.store.saveTask(task)
        if !legacy {
            let request = TaskRequest(
                id: task.id, agent: TaskAgent(id: "fake", name: "Fake"), parent: parentRef,
                parentAgentName: "Fake", title: "work", text: "work", prompt: "work")
            var receipt = HostDelegationReceipt(intent: .init(request), parentID: parent.id)
            receipt.childID = child.id
            try rig.core.tasks.persistReceipt("receipt", receipt)
        }
        // Load legacy task records from the store before stopping the entire old tree.
        _ = rig.core.tasks.stopDelegations(of: legacy ? parent : child)
        let restarted = try HostCore(configuration: rig.core.configuration)
        #expect(restarted.tasks.wasStoppedDelegation(childTurn))
        #expect(restarted.tasks.wasStoppedDelegation(parentTurn) == legacy)
        #expect(!restarted.tasks.wasStoppedDelegation(unrelatedTurn))
        let later = UnfinishedTurn(sessionID: child.id, prompt: OutgoingPrompt(text: "later"), kind: .prompt)
        #expect(!restarted.tasks.wasStoppedDelegation(later))
    }
}
