import Foundation

/// One prompt turn: the prompt that started it and everything the agent did until the next prompt.
/// Messages steered into a running turn belong to it.
public struct TranscriptTurn: Hashable, Sendable, Identifiable {
    /// The id of the turn's first item.
    public let id: String
    /// Where the turn's items sit in `SessionState.items`.
    public let items: Range<Int>
    /// Goes up whenever one of the turn's items is added or changes, so whatever is worked out from
    /// a turn (a transcript's rows for it) can be kept until the turn changes.
    public let revision: Int
    /// When a live turn started and ended. Replayed history has no times.
    public var startedAt: Date?
    public var endedAt: Date?
    /// How the turn ended, once it has: a live turn's from the agent's answer, a replayed one's only
    /// when the agent's history says the user stopped it.
    public var stopReason: StopReason?
    /// Output the agent sent after its turn was stopped, which isn't part of that turn's flow. It opens
    /// with a notice saying so, and has no prompt or clock of its own.
    public var isLateOutput = false
    /// A live turn that hasn't ended. The agent may still have died without ending it, so pair this
    /// with the session's own phase before showing a clock.
    public var isOpen: Bool {
        startedAt != nil && endedAt == nil
    }

    /// How long a finished live turn took.
    public var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

/// When a live turn started and how it ended.
struct TurnClock: Hashable, Sendable {
    var startedAt: Date
    var endedAt: Date?
    var stopReason: StopReason?
    /// When its message failed for a passing reason, while Native waits to send it again.
    var suspendedAt: Date?
}

extension SessionState {
    /// The transcript split into turns, oldest first. A turn starts at each prompt that wasn't
    /// steered into a running turn, and where an agent's output after a stop begins; anything before
    /// the first prompt (a subagent's hand-off, say) is a turn of its own.
    public var turns: [TranscriptTurn] {
        var starts = turnStarts
        if !items.isEmpty, starts.first != 0 {
            starts.insert(0, at: 0)
        }
        return starts.indices.map { position in
            let start = starts[position]
            let end = position + 1 < starts.count ? starts[position + 1] : items.count
            let clock = turnClocks[start]
            return TranscriptTurn(
                id: items[start].id, items: start..<end, revision: revision(ofTurnAt: start),
                startedAt: clock?.startedAt, endedAt: clock?.endedAt,
                stopReason: clock?.stopReason ?? replayedStops[start], isLateOutput: lateOutputStarts.contains(start)
            )
        }
    }

    /// What a turn did, for its folded summary, its footer and the "done" notification.
    public func summary(of turn: TranscriptTurn) -> TurnSummary {
        // Turns without tool work have nothing kept, and nothing much to count.
        var summary = cachedSummary(of: turn) ?? TurnSummary(items: items[turn.items])
        summary.duration = turn.duration
        summary.stopReason = turn.stopReason
        return summary
    }

    /// When the reasoning at `index` started and, once the agent moved on, ended. Nil for anything
    /// but a live thought. It starts when the item before it settled: agents often think in silence
    /// and send a summary of the thought at its end (Codex sends a 30-second thought in its last
    /// second), so the first chunk would time only the summary. The end is when the agent produced
    /// its next item, or its last thought chunk when nothing followed; while it's still the newest
    /// item of the open turn, there's none.
    public func thinkingInterval(at index: Int) -> (start: Date, end: Date?)? {
        guard items.indices.contains(index), case .message(let thought) = items[index], thought.role == .thought,
            let firstChunk = thought.startedAt
        else { return nil }
        let settled = index > 0 ? items[index - 1].settledAt : nil
        let start = settled.map { min($0, firstChunk) } ?? firstChunk
        if index + 1 < items.count {
            return (start, items[index + 1].startedAt ?? thought.updatedAt)
        }
        let isStreaming = openTurn.map { $0 <= index } ?? false
        return (start, isStreaming ? nil : thought.updatedAt)
    }

    /// Since when the running turn has shown nothing new: the moment its newest item settled (the
    /// prompt was sent, a reply stopped streaming, a tool call finished), which is when the agent
    /// went back to thinking. Nil when no live turn runs, or while its newest item is a thought or a
    /// tool call still running, which have clocks of their own.
    public var quietSince: Date? {
        guard let openTurn, let last = items.last, items.count > openTurn else { return nil }
        if case .message(let message) = last, message.role == .thought { return nil }
        return last.settledAt
    }
}

extension TranscriptItem {
    /// When a live item began; nil for replayed history and items without a clock.
    public var startedAt: Date? {
        switch self {
        case .message(let message): message.startedAt
        case .toolCall(let call): call.startedAt
        case .notice, .subagent, .sessionMessage: nil
        }
    }

    /// When a live item last changed for good: a message's last chunk, a tool call's finish. Nil for
    /// replayed history and for a tool call still running.
    var settledAt: Date? {
        switch self {
        case .message(let message): message.updatedAt
        case .toolCall(let call): call.finishedAt
        case .notice, .subagent, .sessionMessage: nil
        }
    }
}

/// What one turn did, in counts: the facts behind "Explored 6 files, edited 3 files, ran 4
/// commands" and "1m 12s · 7 files changed +120 −14".
public struct TurnSummary: Hashable, Sendable {
    /// Distinct files the agent read.
    public var filesRead = 0
    public var searches = 0
    public var commands = 0
    /// Fetches, MCP tools and anything else that isn't reading, searching, editing or running.
    public var otherTools = 0
    /// Files the turn's completed edits touched, in the order first touched.
    public var changedFiles: [ChangedFile] = []
    public var subagents = 0
    /// How long the turn took; nil for replayed history and turns still running.
    public var duration: TimeInterval?
    public var stopReason: StopReason?

    public struct ChangedFile: Hashable, Sendable {
        public var path: String
        public var added = 0
        public var removed = 0
    }

    public var linesAdded: Int {
        changedFiles.reduce(0) { $0 + $1.added }
    }

    public var linesRemoved: Int {
        changedFiles.reduce(0) { $0 + $1.removed }
    }

    public init(items: some Collection<TranscriptItem>, duration: TimeInterval? = nil, stopReason: StopReason? = nil) {
        self.duration = duration
        self.stopReason = stopReason
        var read = Set<String>()
        for item in items {
            switch item {
            case .toolCall(let call):
                count(call, reads: &read)
            case .subagent:
                subagents += 1
            case .message, .notice, .sessionMessage:
                break
            }
        }
        filesRead = read.count
    }

    private mutating func count(_ call: ToolCallState, reads: inout Set<String>) {
        let diffs = call.content.compactMap { content -> FileDiff? in
            if case .diff(let diff) = content { diff } else { nil }
        }
        if !diffs.isEmpty || [.edit, .delete, .move].contains(call.kind) {
            // Rejected or failed edits changed nothing.
            guard call.status == .completed else { return }
            for diff in diffs {
                let lines = diff.lineCounts
                change(diff.path, added: lines.added, removed: lines.removed)
            }
            if diffs.isEmpty, let path = call.locations.first?.path {
                change(path, added: 0, removed: 0)
            }
            return
        }
        switch call.kind {
        case .read: reads.insert(call.locations.first?.path ?? call.title)
        case .search: searches += 1
        case .execute: commands += 1
        // Plans and mode switches aren't tool work worth counting.
        case .think, .switchMode: break
        case .fetch, .other, .edit, .delete, .move: otherTools += 1
        }
    }

    private mutating func change(_ path: String, added: Int, removed: Int) {
        if let index = changedFiles.firstIndex(where: { $0.path == path }) {
            changedFiles[index].added += added
            changedFiles[index].removed += removed
        } else {
            changedFiles.append(ChangedFile(path: path, added: added, removed: removed))
        }
    }

    /// The turn's tool work in one sentence ("Explored 6 files, edited 3 files, ran 4 commands"),
    /// or nil when it used no tools.
    public var activityDescription: String? {
        func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
            "\(count) \(count == 1 ? singular : plural)"
        }
        let parts = [
            filesRead > 0 ? "explored \(counted(filesRead, "file", "files"))" : nil,
            searches > 0 ? "ran \(counted(searches, "search", "searches"))" : nil,
            changedFiles.isEmpty ? nil : "edited \(counted(changedFiles.count, "file", "files"))",
            commands > 0 ? "ran \(counted(commands, "command", "commands"))" : nil,
            otherTools > 0 ? "used \(counted(otherTools, "tool", "tools"))" : nil,
        ].compactMap(\.self)
        guard let first = parts.first else { return nil }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: ", ")
    }
}
