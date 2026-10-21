import Foundation
import MCP

/// Does the work behind the tools sessions hand each other tasks with.
///
/// A session reaches its own tasks, and, when it's a task itself, its parent ("parent") and its
/// siblings (the parent's other tasks). It can read and message any of them, but only cancel its
/// own. Tasks are remembered by the runtime for good, and reopened when a tool needs one.
public struct TaskOrchestrator: Sendable {
    public let runtime: any TaskRuntime

    public init(runtime: any TaskRuntime) {
        self.runtime = runtime
    }

    /// Another session as a caller sees it.
    struct Peer {
        enum Relation: String {
            case parent
            /// A task the caller started.
            case child
            /// Another task of the caller's parent.
            case sibling
        }

        /// The id the caller uses for it: a task id, or "parent".
        let id: String
        let session: TaskSessionRef
        let agentName: String
        let title: String?
        let relation: Relation
        /// Its record, for every peer but the parent: what reopens it after a restart.
        let task: OrchestrationTask?

        var label: String {
            relation == .parent ? "your parent task (\(agentName))" : task?.label ?? id
        }

        init(parentOf own: OrchestrationTask) {
            id = "parent"
            session = own.parent
            agentName = own.parentAgentName
            title = nil
            relation = .parent
            task = nil
        }

        init(_ task: OrchestrationTask, relation: Relation) {
            id = task.id
            session = task.session
            agentName = task.agentName
            title = task.title
            self.relation = relation
            self.task = task
        }
    }

    /// The caller's own place among the tasks, read once per tool call.
    struct Place {
        let session: TaskSessionRef?
        /// The task the caller is, when it's one.
        let own: OrchestrationTask?
        let tasks: [OrchestrationTask]

        /// The sessions the caller can reach: its parent, its own tasks, then its siblings.
        var peers: [Peer] {
            guard let session else { return [] }
            var peers: [Peer] = []
            if let own {
                peers.append(Peer(parentOf: own))
            }
            peers += tasks.filter { $0.parent == session }.map { Peer($0, relation: .child) }
            if let own {
                peers += tasks.filter { $0.parent == own.parent && $0.session != session }.map {
                    Peer($0, relation: .sibling)
                }
            }
            return peers
        }
    }

    // MARK: - Tools

    public func listAgents(for caller: OrchestrationCaller) async throws -> MCPToolResult {
        try await requireReady()
        let agents = await runtime.taskAgents()
        let lines = agents.map { agent in
            "- \(agent.id): \(agent.name)" + (agent.id == caller.agent ? " (the agent you are)" : "")
        }
        let structured: JSON = [
            "agents": .array(
                agents.map {
                    ["id": .string($0.id), "name": .string($0.name), "is_you": .bool($0.id == caller.agent)]
                })
        ]
        return MCPToolResult(
            text: "Agents you can start tasks on (pass the id as `agent`):\n" + lines.joined(separator: "\n"),
            structuredContent: structured)
    }

    public func startTask(
        agent id: String, prompt: String, title: String?, for caller: OrchestrationCaller
    ) async throws -> MCPToolResult {
        try await requireReady()
        let agents = await runtime.taskAgents()
        guard let agent = agents.first(where: { $0.id == id }) else {
            throw MCPToolError(
                "There's no agent \"\(id)\". Available agents: \(agents.map(\.id).joined(separator: ", ")).")
        }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw MCPToolError("The prompt is empty; say what the task should do.") }
        let parent = try await requireSession(of: caller)
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? Self.headline(of: prompt)
        let parentAgentName = agents.first { $0.id == caller.agent }?.name ?? caller.agent

        let request = TaskRequest(
            id: OrchestrationTask.newID(avoiding: Set(await runtime.tasks().map(\.id))), agent: agent, parent: parent,
            parentAgentName: parentAgentName, title: title, text: prompt,
            prompt: TaskPromptFrame.task(prompt, fromParent: parentAgentName))
        let task: OrchestrationTask
        do {
            task = try await runtime.startTask(request)
        } catch {
            throw MCPToolError("Couldn't start the task on \(agent.name): \(error.localizedDescription)")
        }
        var result = report(Peer(task, relation: .child), await runtime.snapshot(of: task.session))
        result.text =
            "Started \(task.label). It runs in the background; call wait_for_task with task_id \"\(task.id)\" for its reply."
        return result
    }

    public func listTasks(for caller: OrchestrationCaller) async throws -> MCPToolResult {
        try await requireReady()
        let place = await place(of: caller)
        let peers = place.peers
        var statuses: [String: String] = [:]
        for peer in peers {
            statuses[peer.id] = await runtime.snapshot(of: peer.session)?.status.rawValue ?? "closed"
        }

        var lines: [String] = []
        if let own = place.own {
            lines.append("You are \(own.label), started by your parent task.")
        }
        if peers.isEmpty {
            lines.append("You haven't started any tasks.")
        } else {
            lines.append(
                "Tasks you can reach (pass the id to send_message, wait_for_task or get_task; a closed one reopens):"
            )
            for peer in peers {
                let role =
                    switch peer.relation {
                    case .parent: "parent: \(peer.label)"
                    case .child: "\(peer.label), a task you started"
                    case .sibling: "\(peer.label), a sibling task your parent started"
                    }
                lines.append("- \(role): \(statuses[peer.id] ?? "closed")")
            }
        }

        let entries = peers.map { peer in
            var entry: [String: JSON] = [
                "id": .string(peer.id), "agent": .string(peer.session.agent),
                "relation": .string(peer.relation.rawValue), "status": .string(statuses[peer.id] ?? "closed"),
            ]
            entry["title"] = peer.title.map(JSON.string)
            return JSON.object(entry)
        }
        var structured: [String: JSON] = ["tasks": .array(entries)]
        structured["you"] = place.own.map { .string($0.id) }
        return MCPToolResult(text: lines.joined(separator: "\n"), structuredContent: .object(structured))
    }

    public func waitForTask(
        _ id: String, timeout: Duration, for caller: OrchestrationCaller
    ) async throws
        -> MCPToolResult
    {
        try await requireReady()
        let peer = try await openPeer(id, of: caller)
        await runtime.settle(peer.session, timeout: timeout)
        return report(peer, await runtime.snapshot(of: peer.session), waited: true)
    }

    public func getTask(_ id: String, for caller: OrchestrationCaller) async throws -> MCPToolResult {
        try await requireReady()
        let peer = try await openPeer(id, of: caller)
        return report(peer, await runtime.snapshot(of: peer.session))
    }

    public func sendMessage(
        to id: String, message text: String, for caller: OrchestrationCaller
    ) async throws
        -> MCPToolResult
    {
        try await requireReady()
        let place = await place(of: caller)
        let recipient = try await openPeer(id, in: place)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MCPToolError("The message is empty.") }
        guard await runtime.snapshot(of: recipient.session) != nil else {
            throw MCPToolError("This task is no longer open in Native: \(recipient.label).")
        }
        guard let sender = place.session else { throw Self.notOpen }
        let message = TaskMessage(
            sender: sender, recipient: recipient.session, text: text,
            prompt: TaskPromptFrame.message(text, from: frameSender(from: caller, in: place, to: recipient)))
        let delivery: TaskMessage.Delivery
        do {
            delivery = try await runtime.deliver(message)
        } catch {
            throw MCPToolError("Couldn't deliver the message to \(recipient.label): \(error.localizedDescription)")
        }
        let how =
            switch delivery {
            case .steered: "It was added to the turn it's working on."
            case .queued: "It's queued for when it finishes its current turn."
            case .prompted: "It was idle, so the message started a new turn."
            }
        return MCPToolResult(
            text:
                "Sent to \(recipient.label). \(how) Nothing waits for a reply; call wait_for_task with task_id \"\(recipient.id)\" if you want one.",
            structuredContent: ["to": .string(recipient.id), "delivery": .string(delivery.rawValue)]
        )
    }

    public func cancelTask(_ id: String, for caller: OrchestrationCaller) async throws -> MCPToolResult {
        try await requireReady()
        let peer = try peer(id, in: await place(of: caller))
        guard peer.relation == .child else {
            throw MCPToolError("You can only cancel tasks you started, and \(peer.label) isn't one of them.")
        }
        guard await runtime.snapshot(of: peer.session) != nil else {
            // A task that isn't open isn't running anything to cancel.
            return report(peer, nil)
        }
        await runtime.cancelTask(peer.session)
        // The agent confirms by ending the turn, which is usually quick.
        await runtime.settle(peer.session, timeout: .seconds(10))
        return report(peer, await runtime.snapshot(of: peer.session))
    }

    /// Native's skills the caller's session may read: all but those switched off for it.
    public func skills(_ skills: [NativeSkill], for caller: OrchestrationCaller) async -> [NativeSkill] {
        let disabled = await runtime.disabledSkills(of: caller.clientID)
        return skills.filter { !disabled.contains($0.id) }
    }

    // MARK: - Messages

    /// Who a message is from, as its recipient knows them.
    private func frameSender(
        from caller: OrchestrationCaller, in place: Place, to recipient: Peer
    )
        -> TaskPromptFrame.Sender
    {
        if recipient.relation == .child {
            return .parent(agent: recipient.task?.parentAgentName ?? caller.agent)
        }
        // Only a task reaches a parent or siblings.
        if recipient.relation == .parent {
            return .task(id: place.own?.id ?? "", label: place.own?.label ?? "")
        }
        return .sibling(id: place.own?.id ?? "", label: place.own?.label ?? "")
    }

    // MARK: - Reports

    private func report(_ peer: Peer, _ snapshot: TaskSnapshot?, waited: Bool = false) -> MCPToolResult {
        var structured: [String: JSON] = [
            "task_id": .string(peer.id), "agent": .string(peer.session.agent),
            "relation": .string(peer.relation.rawValue),
        ]
        structured["title"] = peer.title.map(JSON.string)
        let name = peer.relation == .parent ? "Your parent task (\(peer.agentName))" : peer.label
        guard let snapshot else {
            structured["status"] = "failed"
            structured["detail"] = "The task is no longer open in Native."
            return MCPToolResult(
                text: "\(name) is no longer open in Native.", structuredContent: .object(structured))
        }
        structured["status"] = .string(snapshot.status.rawValue)
        structured["reply"] = snapshot.reply.map(JSON.string)
        structured["detail"] = snapshot.detail.map(JSON.string)

        let keepWaiting = waited ? " Call wait_for_task again to keep waiting." : ""
        let state =
            switch snapshot.status {
            case .running: "is still running.\(keepWaiting)"
            case .needsApproval:
                "is waiting for the user to approve \(snapshot.detail ?? "a tool call") in Native. It continues once they answer.\(keepWaiting)"
            case .idle: "finished its turn" + (snapshot.detail.map { " (\($0))" } ?? "") + "."
            case .failed: "failed: \(snapshot.detail ?? "its agent stopped running")."
            case .cancelled: "was cancelled."
            }
        var text = "\(name) \(state)"
        switch (snapshot.status, snapshot.reply) {
        case (.running, let reply?), (.needsApproval, let reply?): text += "\n\nReply so far:\n\(reply)"
        case (_, let reply?): text += "\n\nReply:\n\(reply)"
        case (.idle, nil): text += " It didn't reply."
        case (_, nil): break
        }
        return MCPToolResult(text: text, structuredContent: .object(structured))
    }

    // MARK: - Lookups

    private static let notOpen = MCPToolError("Native doesn't have your task open, so it can't act for it.")

    private func requireReady() async throws {
        guard await runtime.isReady else {
            throw MCPToolError("Native isn't ready to run tasks yet. Try again shortly.")
        }
    }

    private func requireSession(of caller: OrchestrationCaller) async throws -> TaskSessionRef {
        guard let session = await runtime.session(of: caller.clientID) else { throw Self.notOpen }
        return session
    }

    private func place(of caller: OrchestrationCaller) async -> Place {
        let session = await runtime.session(of: caller.clientID)
        let tasks = await runtime.tasks()
        return Place(session: session, own: session.flatMap { key in tasks.first { $0.session == key } }, tasks: tasks)
    }

    private func peer(_ id: String, in place: Place) throws -> Peer {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let peers = place.peers
        guard let peer = peers.first(where: { $0.id == id }) else {
            let reachable =
                peers.isEmpty
                ? "It hasn't started any tasks and isn't one itself."
                : "It can reach: \(peers.map(\.id).joined(separator: ", "))."
            throw MCPToolError("This task can't reach a task \"\(id)\". \(reachable)")
        }
        return peer
    }

    private func openPeer(_ id: String, of caller: OrchestrationCaller) async throws -> Peer {
        try await openPeer(id, in: await place(of: caller))
    }

    /// The peer, reopened first if it's a task that isn't open (after a restart).
    private func openPeer(_ id: String, in place: Place) async throws -> Peer {
        let peer = try peer(id, in: place)
        if let task = peer.task, await runtime.snapshot(of: peer.session) == nil {
            do {
                try await runtime.openTask(task)
            } catch {
                throw MCPToolError("Couldn't reopen \(peer.label): \(error.localizedDescription)")
            }
        }
        return peer
    }

    /// A title for a task the calling agent didn't name: the start of its first line.
    static func headline(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
