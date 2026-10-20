import ACP
import Foundation
import NativeHostProtocol

/// What agents did while no client was looking ("While you were away", `docs/durability.md`): the
/// host's activity journal since the last entry a client showed, folded into one item per task and a
/// headline. Every client builds it the same way, so the Mac, the iPad and the iPhone tell one story.
public struct AwaySummary: Hashable, Sendable {
    /// One task and what became of it.
    public struct Item: Hashable, Sendable, Identifiable {
        public enum Outcome: Hashable, Sendable {
            /// A tool call waits for approval; the tool's title, when the agent gave one.
            case needsApproval(String?)
            /// The agent asked the user something.
            case asked(String?)
            /// The turn failed, or the agent couldn't be brought back; why, when known.
            case failed(String?)
            case finished
            /// Still working, after Native brought it back from an interruption.
            case working
        }

        public var id: HostSessionID
        /// The session's agent and the agent's id for it, for opening the task.
        public var agentID: String?
        public var agentSessionID: SessionID?
        /// The title, or the agent's name, the host knew the session by.
        public var subject: String
        public var outcome: Outcome
        /// When the outcome happened.
        public var at: Date
        /// Interruptions Native recovered this task from, oldest first.
        public var recoveries: [RecoveryNote]

        /// Whether the user has something to do here.
        public var needsUser: Bool {
            switch outcome {
            case .needsApproval, .asked: true
            case .failed, .finished, .working: false
            }
        }
    }

    /// Tasks that need the user first, then failures, then the rest; newest first within each.
    public var items: [Item]
    /// Every interruption Native recovered from, all tasks together, oldest first.
    public var recoveries: [RecoveryNote]
    /// The newest entry folded in: the next summary starts after it.
    public var lastEntryID: Int64
    /// When the first thing in the summary happened.
    public var since: Date

    /// Folds `entries` (oldest first) with what the host's sessions look like now. Nil when nothing
    /// in them is worth telling: the user's own stops and the host's bookkeeping aren't news.
    public init?(entries: [ActivityEntry], sessions: [HostSessionSummary]) {
        guard let last = entries.last else { return nil }
        let current = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [HostSessionID: Item] = [:]
        var recoveries: [RecoveryNote] = []
        var since: Date?

        for entry in entries {
            guard let sessionID = entry.sessionID else { continue }
            let summary = current[sessionID]
            var item =
                items[sessionID]
                ?? Item(
                    id: sessionID, agentID: entry.agentID ?? summary?.agentID,
                    agentSessionID: entry.agentSessionID ?? summary?.agentSessionID,
                    subject: entry.subject ?? summary?.title ?? summary?.agentName ?? "A task", outcome: .working,
                    at: entry.at, recoveries: [])
            guard let outcome = Self.outcome(of: entry, item: &item, summary: summary) else { continue }
            if let note = entry.recovery, entry.kind == .recovered {
                recoveries.append(note)
            }
            item.outcome = outcome
            item.at = entry.at
            items[sessionID] = item
            since = since ?? entry.at
        }

        guard let since else { return nil }
        self.items = items.values.sorted { lhs, rhs in
            let ranks = (Self.rank(lhs.outcome), Self.rank(rhs.outcome))
            return ranks.0 != ranks.1 ? ranks.0 < ranks.1 : lhs.at > rhs.at
        }
        self.recoveries = recoveries
        lastEntryID = last.id
        self.since = since
    }

    /// What `entry` makes of its task, or nil when it isn't news. An approval that's no longer waiting
    /// (given on another device, or withdrawn when the agent restarted) is left out.
    private static func outcome(
        of entry: ActivityEntry, item: inout Item, summary: HostSessionSummary?
    )
        -> Item.Outcome?
    {
        switch entry.kind {
        case .turnFinished: return .finished
        case .turnFailed: return .failed(entry.detail)
        case .approvalNeeded:
            return summary?.needsApproval == true ? .needsApproval(entry.detail) : nil
        case .recovered:
            guard let note = entry.recovery else { return nil }
            item.recoveries.append(note)
            switch note.action {
            case .failed, .paused: return .failed(note.sentence())
            default: return .working
            }
        default:
            return nil
        }
    }

    private static func rank(_ outcome: Item.Outcome) -> Int {
        switch outcome {
        case .needsApproval, .asked: 0
        case .failed: 1
        case .finished: 2
        case .working: 3
        }
    }

    // MARK: - Wording

    /// One or two sentences: what became of the tasks, then what Native recovered from, as in
    /// "3 tasks finished and 1 needs your approval. Claude Code stopped once and Native resumed it."
    public var headline: String {
        [outcomeSentence, recoverySentence].compactMap(\.self).joined(separator: " ")
    }

    private var outcomeSentence: String? {
        let count = { (matches: (Item.Outcome) -> Bool) in items.count(where: { matches($0.outcome) }) }
        let approvals = count { if case .needsApproval = $0 { true } else { false } }
        let questions = count { if case .asked = $0 { true } else { false } }
        let failed = count { if case .failed = $0 { true } else { false } }
        let finished = count { $0 == .finished }
        let working = count { $0 == .working }
        // The first part carries the noun: "3 tasks finished, 1 failed", "1 task needs your approval".
        var parts: [String] = []
        func add(_ number: Int, _ singular: String, _ plural: String) {
            guard number > 0 else { return }
            let noun = parts.isEmpty ? (number == 1 ? " task" : " tasks") : ""
            parts.append("\(number)\(noun) \(number == 1 ? singular : plural)")
        }
        add(finished, "finished", "finished")
        add(approvals, "needs your approval", "need your approval")
        add(questions, "has a question for you", "have questions for you")
        add(failed, "failed", "failed")
        add(working, "is still working", "are still working")
        guard !parts.isEmpty else { return nil }
        return parts.formatted(.list(type: .and)) + "."
    }

    /// The recoveries, grouped by what happened: an agent's own crashes count each time, while one
    /// host or Mac restart that interrupted several tasks counts once.
    private var recoverySentence: String? {
        let resumed = recoveries.filter { $0.action == .resumed || $0.action == .resent }
        guard !resumed.isEmpty else { return nil }
        var incidents: [(cause: RecoveryNote.Cause, agent: String, times: Int)] = []
        var hostRestarts: Set<Date> = []
        for note in resumed {
            if note.cause == .agentStopped || note.cause == .unknown {
                if let index = incidents.firstIndex(where: { $0.cause == .agentStopped && $0.agent == note.agentName })
                {
                    incidents[index].times += 1
                } else {
                    incidents.append((.agentStopped, note.agentName, 1))
                }
            } else if hostRestarts.insert(note.interruptedAt).inserted {
                if let index = incidents.firstIndex(where: { $0.cause == note.cause }) {
                    incidents[index].times += 1
                } else {
                    incidents.append((note.cause, "", 1))
                }
            }
        }
        guard incidents.count <= 2 else {
            return "Native recovered your tasks from \(resumed.count) interruptions."
        }
        return incidents.map { incident in
            let times = Self.times(incident.times)
            return switch incident.cause {
            case .hostStopped:
                incident.times == 1
                    ? "Native's background host stopped unexpectedly, and Native resumed your tasks."
                    : "Native's background host stopped unexpectedly \(times); Native resumed your tasks each time."
            case .hostUpdated: "Native's background host restarted to update and resumed your tasks."
            case .systemRestarted: "Your Mac restarted, and Native resumed your tasks."
            default:
                incident.times == 1
                    ? "\(incident.agent) stopped once and Native resumed it."
                    : "\(incident.agent) stopped \(times) and Native resumed it each time."
            }
        }
        .joined(separator: " ")
    }

    private static func times(_ count: Int) -> String {
        switch count {
        case 1: "once"
        case 2: "twice"
        default: "\(count) times"
        }
    }
}
