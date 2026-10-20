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
    /// Where the running turn's own items start in `mirror`, to tell whether it got anywhere.
    var turnItemsStart = 0
    var queue: [StoredQueueItem] = []
    /// Messages removed from the queue, newest last, so `_native/queue/restore` can put one back.
    var removedFromQueue: [OutgoingPrompt] = []
    /// Permission requests waiting on the user, by tool call: the agent's request id to answer.
    var pendingPermissions: [String: RequestID] = [:]
    /// Questions waiting on the user, oldest first: the host's id for each and the agent's request.
    var pendingQuestions: [(id: String, request: RequestID)] = []
    var supportsSteering = false
    var problem: String?
    /// The agent process doesn't have this session loaded (the host or the agent restarted since).
    var needsLoad: Bool
    /// The load in flight, shared by everyone who needs it.
    var loading: Task<Void, any Error>?
    /// Set when the user cancels while recovery is under way, so it stops.
    var isRecoveryCancelled = false
    /// When stop was first asked for in the running turn; the agent has until the grace period
    /// ends to confirm.
    var stopRequestedAt: Date?
    var stopTimeout: Task<Void, Never>?
    /// The queued message to send once the turn being stopped ends ("Send Now" on an agent that
    /// can't steer).
    var sendAfterStop: UUID?
    /// A prompt that failed for a passing reason goes out again then; it waits at the queue's front.
    var retryAt: Date?
    var retryTask: Task<Void, Never>?
    /// Retries of the current message so far (`TurnRetry.delays`).
    var retryAttempts = 0
    /// Collecting a hidden command's reply, while one runs.
    var hiddenCommand: HiddenCommandCapture?
    /// The last hidden command's reply, until the next turn starts: copies of it that arrive late
    /// are dropped.
    var hiddenCommandEcho: HiddenCommandCapture?
    /// The transcript as the events describe it, folded only when the host reads it (at turn
    /// boundaries and after a replay), so streaming doesn't decode every update twice.
    var mirror: SessionMirror {
        for event in log[foldedThrough...] {
            folded.apply(event)
        }
        foldedThrough = log.endIndex
        return folded
    }
    private var folded = SessionMirror()
    private var foldedThrough = 0
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
            folded = SessionMirror()
            foldedThrough = 0
        }
        log.append(event)
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

    var isStopping: Bool {
        stopRequestedAt != nil
    }

    /// Whether anything is under way that stopping the agent would cut off.
    var isWorking: Bool {
        turn != nil || phase == .recovering || hiddenCommand != nil || retryAt != nil
            || (!queue.isEmpty && !record.isQueuePaused)
    }

    /// Whether the running turn produced anything: an answer, a tool call, a subagent.
    var turnMadeProgress: Bool {
        mirror.state.items.dropFirst(turnItemsStart).contains { item in
            switch item {
            case .message(let message): message.role != .user
            case .toolCall, .subagent: true
            default: false
            }
        }
    }

    var summary: HostSessionSummary {
        HostSessionSummary(
            id: record.id, agentID: record.agentID, agentName: agentName, agentSessionID: record.agentSessionID,
            cwd: record.cwd,
            parentID: record.parentID, origin: record.origin, title: record.title, phase: phase,
            needsApproval: !pendingPermissions.isEmpty || !pendingQuestions.isEmpty,
            queue: queue.map(\.prompt.queued), isQueuePaused: record.isQueuePaused, supportsSteering: supportsSteering,
            lastActivity: record.lastActivity, lastStopReason: record.lastStopReason, problem: problem,
            isStopping: isStopping, isRunningHiddenCommand: hiddenCommand != nil, retryAt: retryAt
        )
    }

    /// The title in a `session_info_update`.
    private static func title(in update: JSONValue) -> String? {
        guard update["sessionUpdate"]?.stringValue == "session_info_update" else { return nil }
        return update["title"]?.stringValue
    }
}
