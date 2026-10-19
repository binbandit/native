import ACP

/// A run of tool work in one turn too long to show row by row: consecutive tool calls (and the
/// reasoning between them) beyond `threshold`, condensed into one list that scrolls (`ToolRunView`).
/// Requests waiting on the user and anything the agent says end a run.
struct TranscriptActivityRun: Identifiable, Equatable {
    /// More calls than this in a row condense. About as many rows as the condensed list shows, so
    /// condensing never takes more room than the rows would.
    static let threshold = 6

    /// The run's transcript items. A copy rather than a slice: lines are kept per turn, and a slice
    /// would keep the whole transcript of its day alive with it.
    let items: [TranscriptItem]
    /// Where the first item sits in `SessionState.items`.
    let firstIndex: Int
    /// How many transcript rows it stands for.
    let rowCount: Int
    /// When each live thought in the run started and ended, by its index in `items`.
    let thinking: [Int: ThinkingClock]

    /// The first item never changes as the run grows, so the run keeps its identity.
    var id: String {
        "run-\(items.first?.id ?? "")"
    }

    /// Where the run's items sit in `SessionState.items`.
    var transcriptIndices: Range<Int> {
        firstIndex..<firstIndex + items.count
    }

    var calls: [ToolCallState] {
        items.compactMap { item in
            if case .toolCall(let call) = item { call } else { nil }
        }
    }

    /// The run that starts at `rows`' first row, if the tool work there is long enough to condense.
    init?(rows: ArraySlice<(row: TranscriptRow, itemIndex: Int)>, in state: SessionState) {
        let run = rows.prefix { $0.row.isFoldableActivity }
        let callCount = run.reduce(0) { count, entry in count + entry.row.callCount }
        guard callCount > Self.threshold, let first = run.first, let last = run.last else { return nil }
        let range = first.itemIndex..<last.itemIndex + last.row.itemCount
        items = Array(state.items[range])
        firstIndex = range.lowerBound
        rowCount = run.count
        var thinking: [Int: ThinkingClock] = [:]
        for index in range {
            if let interval = state.thinkingInterval(at: index) {
                thinking[index - range.lowerBound] = ThinkingClock(start: interval.start, end: interval.end)
            }
        }
        self.thinking = thinking
    }
}

private extension TranscriptRow {
    var callCount: Int {
        switch self {
        case .exploration(let calls): calls.count
        case .item(.toolCall): 1
        case .item: 0
        }
    }
}
