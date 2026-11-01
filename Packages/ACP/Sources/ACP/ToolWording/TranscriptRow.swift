/// A transcript row: an item as it is, or a run of tool work shown as one line.
public enum TranscriptRow: Identifiable, Hashable, Sendable {
    case item(TranscriptItem)
    /// Two or more tool calls in a row, with the reasoning between them (`ToolWorkGroup`).
    case toolGroup(ToolWorkGroup)

    public var id: String {
        switch self {
        case .item(let item): item.id
        case .toolGroup(let group): group.id
        }
    }

    /// How many transcript items the row shows.
    public var itemCount: Int {
        switch self {
        case .item: 1
        case .toolGroup(let group): group.items.count
        }
    }

    /// Work an earlier turn folds away: tool calls and reasoning. Prose and requests waiting for
    /// the user never fold.
    public var isFoldableActivity: Bool {
        switch self {
        case .toolGroup: true
        case .item(let item): item.isGroupableWork
        }
    }

    /// An output-free poll that can safely be omitted from the transcript.
    public var isPolling: Bool {
        if case .item(.toolCall(let call)) = self { call.isSuppressiblePolling } else { false }
    }

    /// Whether the row is tool work, which reads as one dense block.
    public var isToolActivity: Bool {
        switch self {
        case .toolGroup, .item(.toolCall): true
        case .item: false
        }
    }

    /// Folds each run of tool work holding two or more calls into one group, so a burst of work
    /// takes one line however long it is. A run is the calls and reasoning between two pieces of
    /// anything else: prose, a notice, a subagent, a request waiting for the user, a question. With
    /// `grouping` off every item is its own row.
    public static func rows(from items: some Sequence<TranscriptItem>, grouping: Bool = true) -> [TranscriptRow] {
        rowsWithSources(from: items, grouping: grouping).map(\.row)
    }

    /// Builds rows with their original positions, including the IDs/positions of folded polls.
    /// Clients use this membership for search reveal and per-item reasoning clocks.
    public static func rowsWithSources(
        from items: some Sequence<TranscriptItem>, grouping: Bool = true
    ) -> [TranscriptRowSource] {
        let entries = ToolPollingTranscript.foldingWithSources(Array(items))
        func itemRow(_ entry: (item: TranscriptItem, indices: Set<Int>)) -> TranscriptRowSource {
            TranscriptRowSource(
                row: .item(entry.item), itemIndices: [entry.indices.min() ?? 0], sourceIndices: entry.indices)
        }
        guard grouping else { return entries.map(itemRow) }
        var rows: [TranscriptRowSource] = []
        var run: [(item: TranscriptItem, indices: Set<Int>)] = []
        var calls = 0

        func flush() {
            if calls > 1 {
                let group = ToolWorkGroup(foldedItems: run.map(\.item))
                let visible = run.filter { entry in
                    if case .toolCall(let call) = entry.item { !call.isSuppressiblePolling } else { true }
                }
                rows.append(
                    TranscriptRowSource(
                        row: .toolGroup(group), itemIndices: visible.map { $0.indices.min() ?? 0 },
                        sourceIndices: Set(run.flatMap(\.indices))))
            } else {
                rows += run.map(itemRow)
            }
            run.removeAll()
            calls = 0
        }

        for entry in entries {
            if entry.item.isGroupableWork {
                run.append(entry)
                // Polling only waits on the call before it, so it doesn't make a run worth a group.
                if case .toolCall(let call) = entry.item, !call.isPolling { calls += 1 }
            } else {
                flush()
                rows.append(itemRow(entry))
            }
        }
        flush()
        return rows
    }
}

/// A run of tool work as one line: while it runs, what the agent is doing now ("Reading
/// ToolRow.swift"); once it's done, what it did ("Read 3 files and ran 2 commands"). It opens into
/// the calls and reasoning it stands for.
public struct ToolWorkGroup: Identifiable, Hashable, Sendable {
    /// The calls and the reasoning between them. A copy rather than a slice of the transcript, so a
    /// row never keeps a whole session's items alive.
    public let items: [TranscriptItem]

    public init(items: [TranscriptItem]) {
        self.init(foldedItems: ToolPollingTranscript.folding(items))
    }

    // The row builder has already matched polls across the whole turn. Repeating the match here
    // could associate an orphan poll with a command whose process already finished.
    fileprivate init(foldedItems: [TranscriptItem]) {
        self.items = foldedItems.filter { item in
            if case .toolCall(let call) = item { !call.isSuppressiblePolling } else { true }
        }
    }

    /// The first item never changes as the group grows, so the group keeps its identity.
    public var id: String {
        "group-\(items.first?.id ?? "")"
    }

    /// The group's calls, keeping polling results accessible alongside their originating work.
    public var calls: [ToolCallState] {
        items.compactMap { item in
            if case .toolCall(let call) = item, !call.isSuppressiblePolling { call } else { nil }
        }
    }

    public var isRunning: Bool {
        items.contains { item in
            if case .toolCall(let call) = item { !call.status.isFinished } else { false }
        }
    }

    /// The call the line names while the group is live: the newest one still running (polling
    /// included, so a wait reads as one), else the newest one.
    public var currentCall: ToolCallState? {
        let running = items.last { item in
            if case .toolCall(let call) = item { !call.status.isFinished } else { false }
        }
        if case .toolCall(let call)? = running { return call }
        return calls.last
    }

    /// What the group did, once it's done.
    public var summary: String {
        ToolWorkSummary(calls: calls).sentence ?? "Used tools"
    }

    /// How the group ended when its last call didn't succeed: a failure the agent carried on from
    /// is part of the work, but one it stopped at is worth seeing without opening the group.
    public var outcome: ToolPhase? {
        guard let last = calls.last else { return nil }
        let phase = ToolPhase(last)
        return phase == .completed || phase == .running ? nil : phase
    }
}

extension TranscriptItem {
    /// Tool calls and reasoning, the work a group gathers. A call waiting for the user stays on its
    /// own so its request is never folded away, and so do Claude Code's questions, which read as
    /// their answers.
    var isGroupableWork: Bool {
        switch self {
        case .toolCall(let call): call.permission == nil && call.name != "AskUserQuestion"
        case .message(let message): message.role == .thought
        case .notice, .subagent, .sessionMessage: false
        }
    }
}
