import ACP
import Foundation
import NativeHostProtocol

/// A session the host has open: its durable record, its live state, and the ordered event log that
/// attached clients replay and follow.
@HostActor
final class HostSession {
    var record: StoredSession
    var agentName: String
    var phase: HostSessionPhase
    /// MCP servers handed to the agent for this session, verbatim; given again on every reload.
    var mcpServers: [JSONValue]
    /// The turn running (or being recovered), as the store has it.
    var turn: UnfinishedTurn?
    var queue: [StoredQueueItem] = []
    /// Permission requests waiting on the user, by tool call: the agent's request id to answer.
    var pendingPermissions: [String: RequestID] = [:]
    var supportsSteering = false
    var problem: String?
    /// The agent process doesn't have this session loaded (the host or the agent restarted since).
    var needsLoad: Bool
    /// The load in flight, shared by everyone who needs it.
    var loading: Task<Void, any Error>?
    /// Set when the user cancels while recovery is under way, so it stops.
    var isRecoveryCancelled = false
    /// The transcript as the events describe it; the host reads the agent's replay from it.
    private(set) var mirror = SessionMirror()
    private(set) var log: [HostEvent] = []
    private var nextSeq = 1
    /// Clients following this session's events.
    var subscribers: Set<ClientLink.ID> = []

    init(
        record: StoredSession, agentName: String, phase: HostSessionPhase, needsLoad: Bool, mcpServers: [JSONValue] = []
    ) {
        self.record = record
        self.agentName = agentName
        self.phase = phase
        self.needsLoad = needsLoad
        self.mcpServers = mcpServers
    }

    var id: HostSessionID {
        record.id
    }

    /// Adds an event to the log and returns it, numbered.
    func append(_ payload: HostEvent.Payload, at date: Date = .now) -> HostEvent {
        let event = HostEvent(seq: nextSeq, at: date, payload: payload)
        nextSeq += 1
        if case .reset = payload {
            log = []
        }
        log.append(event)
        mirror.apply(event)
        if case .update(let update) = payload, let title = Self.title(in: update) {
            record.title = title
        }
        return event
    }

    /// What a client attaching with `afterSeq` (from this host run) hasn't seen: everything after it,
    /// or the whole log from its reset.
    func events(after seq: Int?) -> [HostEvent] {
        guard let seq, let first = log.first, seq >= first.seq - 1 else { return log }
        return log.filter { $0.seq > seq }
    }

    var summary: HostSessionSummary {
        HostSessionSummary(
            id: record.id, agentID: record.agentID, agentName: agentName, agentSessionID: record.agentSessionID,
            cwd: record.cwd,
            parentID: record.parentID, origin: record.origin, title: record.title, phase: phase,
            needsApproval: !pendingPermissions.isEmpty,
            queue: queue.map(\.prompt), isQueuePaused: record.isQueuePaused, supportsSteering: supportsSteering,
            lastActivity: record.lastActivity, lastStopReason: record.lastStopReason, problem: problem
        )
    }

    /// The title in a `session_info_update`.
    private static func title(in update: JSONValue) -> String? {
        guard update["sessionUpdate"]?.stringValue == "session_info_update" else { return nil }
        return update["title"]?.stringValue
    }
}
