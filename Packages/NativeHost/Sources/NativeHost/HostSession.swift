import ACP
import Foundation
import NativeHostProtocol
import SessionTitling

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
    /// The host unloaded the session while idle and its log still holds the conversation, so the
    /// next load resumes it without a replay (`HostCore+IdleUnload.swift`).
    var reloadsQuietly = false
    /// When the session last logged an event (a turn, an update, a setting), to tell how long it
    /// has sat idle.
    private(set) var lastEventAt = Date.now
    /// The load in flight, shared by everyone who needs it.
    var loading: Task<Void, any Error>?
    /// Config notifications during a load stay private until restoration has settled.
    var loadingConfigOptions: JSONValue?
    /// Settings supplied by the client opening this session. Saved choices always win; after a
    /// successful load the resolved values are durable and these fallbacks are no longer needed.
    var loadConfigDefaults: [String: String] = [:]
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
    /// Identifies the automatic naming request, so its late cleanup cannot clear a newer capture.
    var namingCommandID: UUID?
    /// The last hidden command's reply, until the next turn starts: copies of it that arrive late
    /// are dropped.
    var hiddenCommandEcho: HiddenCommandCapture?
    /// The transcript as the events describe it, folded only when the host reads it (at turn
    /// boundaries and after a replay), so streaming doesn't decode every update.
    var mirror: SessionMirror {
        for event in log[foldedThrough...] {
            if let step = try? decoder.decode(SessionMirror.Step.self, from: event.json) {
                folded.apply(step)
            }
        }
        foldedThrough = log.endIndex
        return folded
    }
    private var folded = SessionMirror()
    private var foldedThrough = 0
    private(set) var log: [LoggedEvent] = []
    private let encoder = HostSession.makeEncoder()
    private let decoder = HostSession.makeDecoder()
    private var nextSeq = 1
    /// Clients following this session's events.
    var subscribers: Set<ClientLink.ID> = []
    /// Native's titles for it (`HostCore+Titles.swift`), as the store keeps them.
    var titleState = SessionTitleState()

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

    /// Adds one of Native's own events to the log and returns it, numbered and encoded.
    func append(_ payload: HostEvent.Payload, at date: Date = .now) -> LoggedEvent {
        if case .reset = payload {
            log = []
            folded = SessionMirror()
            foldedThrough = 0
        }
        let event = HostEvent(seq: nextSeq, at: date, payload: payload)
        // Native's own events always encode; nothing in them is beyond JSON.
        let json = (try? encoder.encode(event)) ?? Data("{}".utf8)
        if case .update(let update) = payload, update["sessionUpdate"]?.stringValue == "session_info_update",
            let title = update["title"]?.stringValue
        {
            record.title = title
        }
        return log(json)
    }

    /// Adds an agent's update to the log, its JSON spliced in as the agent sent it.
    func append(_ update: AgentUpdate, at date: Date = .now) -> LoggedEvent {
        var json = Data(
            #"{"seq":\#(nextSeq),"at":\#(Int64(date.timeIntervalSince1970 * 1_000)),"type":"update","update":"#.utf8)
        json.append(update.json)
        json.append(UInt8(ascii: "}"))
        if update.kind == "session_info_update", let title = update.title {
            record.title = title
        }
        return log(json)
    }

    private func log(_ json: Data) -> LoggedEvent {
        lastEventAt = .now
        let event = LoggedEvent(seq: nextSeq, json: json)
        nextSeq += 1
        log.append(event)
        return event
    }

    /// What a client attaching with `afterSeq` (from this host run) hasn't seen: everything after it,
    /// or the whole log from its reset.
    func events(after seq: Int?) -> ArraySlice<LoggedEvent> {
        guard let seq, let first = log.first, seq >= first.seq - 1 else { return log[...] }
        return log[(log.firstIndex { $0.seq > seq } ?? log.endIndex)...]
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
            isStopping: isStopping, isRunningHiddenCommand: hiddenCommand != nil, retryAt: retryAt,
            titles: titleState.hostTitles
        )
    }

    /// Dates as milliseconds since 1970, as the protocol has them.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

/// One event as the host keeps it: numbered, and encoded once for every client that follows it or
/// attaches later.
struct LoggedEvent {
    let seq: Int
    /// The `HostEvent`, as JSON.
    let json: Data
}
