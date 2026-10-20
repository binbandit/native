import Foundation
import MCP
import Observation

/// Keeps track of the tasks sessions hand each other, and does the work behind the tools.
///
/// A session reaches its own tasks, and, when it's a task itself, its parent ("parent") and its
/// siblings (the parent's other tasks). It can read and message any of them, but only cancel its own.
/// Tasks are remembered across launches, and reopened when their parent is or when a tool needs one.
@MainActor
final class Orchestrator {
    /// The app, once it can run tasks. Until then the tools say so.
    var host: (any OrchestrationHost)?

    /// Another session as a caller sees it.
    private struct Peer {
        enum Relation: String {
            case parent
            /// A task the caller started.
            case child
            /// Another task of the caller's parent.
            case sibling
        }

        /// The id the caller uses for it: a task id, or "parent".
        let id: String
        let session: SessionKey
        let agentName: String
        let title: String?
        let relation: Relation
        /// Its record, for every peer but the parent: what reopens it after a relaunch.
        let task: OrchestrationTask?

        var label: String {
            relation == .parent ? "your parent session (\(agentName))" : task?.label ?? id
        }
    }

    /// In the order they started.
    private var tasks: [OrchestrationTask] {
        didSet { save() }
    }
    /// The sessions handed a URL this launch, by Native's id for them (`SessionContext.clientID`),
    /// which is what their tokens name.
    private var callers: [UUID: OrchestrationCaller] = [:]
    private let defaults: UserDefaults
    private static let tasksKey = "orchestrationTasks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tasks = Self.savedTasks(in: defaults)
    }

    /// The saved record of task `id`, for views that only know the id: a reloaded session replays
    /// its task prompts with the sender's id in their header.
    static func savedTask(id: String, defaults: UserDefaults = .standard) -> OrchestrationTask? {
        savedTasks(in: defaults).first { $0.id == id }
    }

    private static func savedTasks(in defaults: UserDefaults) -> [OrchestrationTask] {
        defaults.data(forKey: tasksKey).flatMap { try? JSONDecoder().decode([OrchestrationTask].self, from: $0) } ?? []
    }

    /// Notes that `session` is being handed its URL, so its token resolves to it. The first time in
    /// a launch for a session the agent already has (one being reopened), its tasks reopen too, so
    /// its transcript shows them again.
    func handedURL(to session: SessionContext) {
        let caller = OrchestrationCaller(clientID: session.clientID, agent: session.agent, cwd: session.cwd)
        guard callers.updateValue(caller, forKey: session.clientID) == nil, let id = session.sessionID else { return }
        reopenTasks(of: SessionKey(agent: session.agent, id: id))
    }

    /// The session a token the server checked names: one handed its URL this launch, else one the
    /// host still runs from an earlier launch. Nil for a session Native no longer has, so closing
    /// a session retires its token.
    func caller(of clientID: UUID) async -> OrchestrationCaller? {
        if let caller = callers[clientID] {
            return caller
        }
        return await host?.caller(of: clientID)
    }

    /// Native's skills the caller's session may read: all but those switched off for it.
    func skills(_ skills: [NativeSkill], for caller: OrchestrationCaller) -> [NativeSkill] {
        let disabled = host?.disabledSkills(of: caller.clientID) ?? []
        return skills.filter { !disabled.contains($0.id) }
    }

    private func reopenTasks(of parent: SessionKey) {
        let children = tasks.filter { $0.parent == parent }
        guard !children.isEmpty else { return }
        Task {
            for task in children {
                try? await host?.openTask(task)
            }
        }
    }

    // MARK: - Tools

    func listAgents(for caller: OrchestrationCaller) throws -> MCPToolResult {
        let agents = try requireHost().taskAgents
        let lines = agents.map { agent in
            "- \(agent.id): \(agent.displayName)" + (agent.id == caller.agent ? " (the agent you are)" : "")
        }
        let structured: JSON = [
            "agents": .array(
                agents.map {
                    [
                        "id": .string($0.id.rawValue), "name": .string($0.displayName),
                        "is_you": .bool($0.id == caller.agent),
                    ]
                })
        ]
        return MCPToolResult(
            text: "Agents you can start tasks on (pass the id as `agent`):\n" + lines.joined(separator: "\n"),
            structuredContent: structured)
    }

    func startTask(
        agent id: String, prompt: String, title: String?, for caller: OrchestrationCaller
    ) async throws -> MCPToolResult {
        let host = try requireHost()
        guard let agent = host.taskAgents.first(where: { $0.id.rawValue == id }) else {
            throw MCPToolError(
                "There's no agent \"\(id)\". Available agents: \(host.taskAgents.map(\.id.rawValue).joined(separator: ", "))."
            )
        }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw MCPToolError("The prompt is empty; say what the task should do.") }
        let parent = try requireCallerKey(caller)
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? Self.headline(of: prompt)

        let request = TaskRequest(
            agent: agent.id, parent: parent, title: title, text: prompt,
            prompt: TaskPromptFrame.task(prompt, fromParent: agentName(caller.agent)))
        let session: SessionKey
        do {
            session = try await host.startTask(request)
        } catch {
            throw MCPToolError("Couldn't start the task on \(agent.displayName): \(error.localizedDescription)")
        }
        let task = OrchestrationTask(
            id: newTaskID(), session: session, agentName: agent.displayName, title: title, parent: parent,
            parentAgentName: agentName(caller.agent))
        tasks.append(task)
        var result = report(peer(for: task, relation: .child), host.taskSnapshot(session))
        result.text =
            "Started \(task.label). It runs in the background; call wait_for_task with task_id \"\(task.id)\" for its reply."
        return result
    }

    func listTasks(for caller: OrchestrationCaller) throws -> MCPToolResult {
        let host = try requireHost()
        let own = callerKey(caller).flatMap { key in tasks.first { $0.session == key } }
        let peers = peers(of: caller)
        let status = { (peer: Peer) in host.taskSnapshot(peer.session)?.status.rawValue ?? "closed" }

        var lines: [String] = []
        if let own {
            lines.append("You are \(own.label), a task your parent session started.")
        }
        if peers.isEmpty {
            lines.append("You haven't started any tasks.")
        } else {
            lines.append(
                "Sessions you can reach (pass the id to send_message, wait_for_task or get_task; a closed one reopens):"
            )
            for peer in peers {
                let role =
                    switch peer.relation {
                    case .parent: "parent: \(peer.label)"
                    case .child: "\(peer.label), a task you started"
                    case .sibling: "\(peer.label), a sibling task your parent started"
                    }
                lines.append("- \(role): \(status(peer))")
            }
        }

        let entries = peers.map { peer in
            var entry: [String: JSON] = [
                "id": .string(peer.id), "agent": .string(peer.session.agent.rawValue),
                "relation": .string(peer.relation.rawValue),
                "status": .string(status(peer)),
            ]
            entry["title"] = peer.title.map(JSON.string)
            return JSON.object(entry)
        }
        var structured: [String: JSON] = ["tasks": .array(entries)]
        structured["you"] = own.map { .string($0.id) }
        return MCPToolResult(text: lines.joined(separator: "\n"), structuredContent: .object(structured))
    }

    func waitForTask(_ id: String, timeout: Duration, for caller: OrchestrationCaller) async throws -> MCPToolResult {
        let peer = try await openPeer(id, of: caller)
        let host = try requireHost()
        await settle(peer.session, host: host, timeout: timeout)
        return report(peer, host.taskSnapshot(peer.session), waited: true)
    }

    func getTask(_ id: String, for caller: OrchestrationCaller) async throws -> MCPToolResult {
        let peer = try await openPeer(id, of: caller)
        return report(peer, try requireHost().taskSnapshot(peer.session))
    }

    func sendMessage(to id: String, message text: String, for caller: OrchestrationCaller) async throws -> MCPToolResult
    {
        let recipient = try await openPeer(id, of: caller)
        let host = try requireHost()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MCPToolError("The message is empty.") }
        guard host.taskSnapshot(recipient.session) != nil else {
            throw MCPToolError("The session of \(recipient.label) is no longer open in Native.")
        }

        let message = TaskMessage(
            sender: try requireCallerKey(caller), recipient: recipient.session, text: text,
            prompt: TaskPromptFrame.message(text, from: frameSender(from: caller, to: recipient)))
        let delivery: TaskMessage.Delivery
        do {
            delivery = try await host.deliver(message)
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

    func cancelTask(_ id: String, for caller: OrchestrationCaller) async throws -> MCPToolResult {
        let peer = try peer(id, of: caller)
        guard peer.relation == .child else {
            throw MCPToolError("You can only cancel tasks you started, and \(peer.label) isn't one of them.")
        }
        let host = try requireHost()
        guard host.taskSnapshot(peer.session) != nil else {
            // A task that isn't open isn't running anything to cancel.
            return report(peer, nil)
        }
        await host.cancelTask(peer.session)
        // The agent confirms by ending the turn, which is usually quick.
        await settle(peer.session, host: host, timeout: .seconds(10))
        return report(peer, host.taskSnapshot(peer.session))
    }

    // MARK: - Messages

    /// Who a message is from, as its recipient knows them.
    private func frameSender(from caller: OrchestrationCaller, to recipient: Peer) -> TaskPromptFrame.Sender {
        if recipient.relation == .child {
            return .parent(agent: agentName(caller.agent))
        }
        // Only a task reaches a parent or siblings.
        let own = callerKey(caller).flatMap { key in tasks.first { $0.session == key } }
        if recipient.relation == .parent {
            return .task(id: own?.id ?? "", label: own?.label ?? "")
        }
        return .sibling(id: own?.id ?? "", label: own?.label ?? "")
    }

    // MARK: - Waiting

    /// Returns once the session's turn isn't running (it ended or needs approval), or after
    /// `timeout`, or when the caller hangs up.
    private func settle(_ session: SessionKey, host: any OrchestrationHost, timeout: Duration) async {
        let statuses = Observations { host.taskSnapshot(session)?.status }
        await withTaskGroup { group in
            group.addTask {
                for await status in statuses where status != .running {
                    return
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Reports

    private func report(_ peer: Peer, _ snapshot: TaskSnapshot?, waited: Bool = false) -> MCPToolResult {
        var structured: [String: JSON] = [
            "task_id": .string(peer.id), "agent": .string(peer.session.agent.rawValue),
            "relation": .string(peer.relation.rawValue),
        ]
        structured["title"] = peer.title.map(JSON.string)
        let name = peer.relation == .parent ? "Your parent session (\(peer.agentName))" : peer.label
        guard let snapshot else {
            structured["status"] = "failed"
            structured["detail"] = "The session is no longer open in Native."
            return MCPToolResult(
                text: "The session of \(name) is no longer open in Native.", structuredContent: .object(structured))
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

    private func requireHost() throws -> any OrchestrationHost {
        guard let host else { throw MCPToolError("Native isn't ready to run tasks yet. Try again shortly.") }
        return host
    }

    private func callerKey(_ caller: OrchestrationCaller) -> SessionKey? {
        host?.sessionKey(of: caller.clientID)
    }

    private func requireCallerKey(_ caller: OrchestrationCaller) throws -> SessionKey {
        guard let key = callerKey(caller) else {
            throw MCPToolError("Native doesn't have your session open, so it can't act for it.")
        }
        return key
    }

    /// The sessions `caller` can reach: its parent, its own tasks, then its siblings.
    private func peers(of caller: OrchestrationCaller) -> [Peer] {
        guard let key = callerKey(caller) else { return [] }
        let own = tasks.first { $0.session == key }
        var peers: [Peer] = []
        if let own {
            peers.append(
                Peer(
                    id: "parent", session: own.parent, agentName: own.parentAgentName, title: nil, relation: .parent,
                    task: nil))
        }
        peers += tasks.filter { $0.parent == key }.map { peer(for: $0, relation: .child) }
        if let own {
            peers += tasks.filter { $0.parent == own.parent && $0.session != key }.map {
                peer(for: $0, relation: .sibling)
            }
        }
        return peers
    }

    private func peer(_ id: String, of caller: OrchestrationCaller) throws -> Peer {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let peers = peers(of: caller)
        guard let peer = peers.first(where: { $0.id == id }) else {
            let reachable =
                peers.isEmpty
                ? "It hasn't started any tasks and isn't one itself."
                : "It can reach: \(peers.map(\.id).joined(separator: ", "))."
            throw MCPToolError("This session can't reach a task \"\(id)\". \(reachable)")
        }
        return peer
    }

    /// The peer, reopened first if it's a task from an earlier launch.
    private func openPeer(_ id: String, of caller: OrchestrationCaller) async throws -> Peer {
        let peer = try peer(id, of: caller)
        if let task = peer.task, let host, host.taskSnapshot(peer.session) == nil {
            do {
                try await host.openTask(task)
            } catch {
                throw MCPToolError("Couldn't reopen \(peer.label): \(error.localizedDescription)")
            }
        }
        return peer
    }

    private func peer(for task: OrchestrationTask, relation: Peer.Relation) -> Peer {
        Peer(
            id: task.id, session: task.session, agentName: task.agentName, title: task.title, relation: relation,
            task: task)
    }

    private func agentName(_ id: AgentDefinition.ID) -> String {
        host?.taskAgents.first { $0.id == id }?.displayName ?? id.rawValue
    }

    /// Short enough for a model to copy reliably.
    private func newTaskID() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        while true {
            let id = "task-" + String((0..<6).map { _ in alphabet[Int.random(in: alphabet.indices)] })
            if !tasks.contains(where: { $0.id == id }) {
                return id
            }
        }
    }

    /// A title for a task the calling agent didn't name: the start of its first line.
    private static func headline(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Self.tasksKey)
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
