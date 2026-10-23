import ACP
import SwiftUI

/// One line of the standard transcript: a row, a long run of tool work condensed into one list,
/// an earlier turn's folded tool work, a finished turn's footer, or the files-changed card after
/// the latest turn.
struct StandardTranscriptLine: Identifiable {
    enum Kind {
        /// A transcript row and the index of its first item; for reasoning, when it started and
        /// ended (`SessionState.thinkingInterval`), worked out here so the row never reads the session.
        case row(TranscriptRow, itemIndex: Int, thinking: ThinkingClock?)
        /// A section of an agent's reply (`String.markdownSections`), the reply being the item at
        /// `itemIndex`. A long reply is a line per section, so the lazy stack lays out and draws only
        /// the sections on screen, and while it streams only the last one changes.
        case replySection(String, isFirst: Bool, itemIndex: Int)
        case artifacts([MessageAttachment], itemIndex: Int)
        /// More tool calls in a row than fit on screen, as one condensed list (`ToolRunView`).
        case activityRun(TranscriptActivityRun)
        /// An earlier turn's tool work as one line ("Explored 6 files, edited 3 files").
        case fold(TranscriptTurn, TurnSummary, isUnfolded: Bool)
        /// How a finished turn went: how it ended, how long it took, what it changed, its agents.
        case footer(
            TranscriptTurn, TurnSummary, ending: TranscriptNotice?, showsChanges: Bool, subagents: [SubagentState])
        /// What the latest turn changed, with the next steps for it.
        case changes(TurnSummary)
        /// A usage limit stopped the turn here (`UsageLimitTranscriptCard`).
        case usageLimit(UsageLimitStop, isLatestTurn: Bool)
    }

    let id: String
    let kind: Kind
    var spacing: CGFloat = 0

    /// Tool work reads as one dense block; everything else gets room to breathe.
    private var isDense: Bool {
        switch kind {
        case .row(let row, _, _): row.isToolActivity
        case .fold, .activityRun: true
        case .replySection, .artifacts, .footer, .changes, .usageLimit: false
        }
    }

    /// Lays out `transcript` turn by turn. With `folding` on, every turn but the latest folds its
    /// tool work into one line (unless the user opened it), and each finished turn closes with a
    /// footer; the latest closes with its changes, once it's done.
    ///
    /// This runs on every update, and a long session has hundreds of turns, so each turn's lines are
    /// kept until the turn changes (`TranscriptTurn.revision`) and only the turn that changed is laid
    /// out again. The earlier turns' lines come back as one list that stays the same (and keeps its
    /// version) until one of those turns changes.
    static func plan(
        _ transcript: TranscriptStyleConfiguration, folding: Bool, unfolded: Set<TranscriptTurn.ID>,
        cache: StandardTranscriptLineCache, detected: TurnDetectedChanges? = nil
    ) -> StandardTranscriptPlan {
        let state = transcript.session.state
        let turns = state.turns
        let keys = turns.indices.map { position in
            let turn = turns[position]
            let isLatest = position == turns.count - 1
            return TurnLinesKey(
                turn: turn, folding: folding, isUnfolded: unfolded.contains(turn.id), isLatest: isLatest,
                isRunning: isLatest && transcript.isWorking, unfoldsExploration: transcript.unfoldsExploration,
                detectedFiles: isLatest && detected?.startedAt == turn.startedAt ? detected?.files : nil)
        }
        func lines(for key: TurnLinesKey) -> [Self] {
            cache.lines(for: key) { Self.lines(for: key, in: state) }
        }
        let earlier = cache.earlierLines(for: keys.dropLast()) { keys in
            var earlier = keys.flatMap(lines(for:))
            space(&earlier, after: nil)
            return earlier
        }
        var latest = keys.last.map(lines(for:)) ?? []
        space(&latest, after: earlier.lines.last)
        return StandardTranscriptPlan(earlier: earlier, latest: latest)
    }

    /// Spaces each line from the one above it, the first from `previous`.
    private static func space(_ lines: inout [Self], after previous: Self?) {
        for index in lines.indices {
            let above = index > lines.startIndex ? lines[index - 1] : previous
            lines[index].spacing = above.map { spacing(between: $0, and: lines[index]) } ?? 0
        }
    }

    /// One turn's lines, before spacing.
    private static func lines(for key: TurnLinesKey, in state: SessionState) -> [StandardTranscriptLine] {
        let turn = key.turn
        let turnItems = Array(state.items[turn.items])
        let rows = key.unfoldsExploration ? turnItems.map(TranscriptRow.item) : TranscriptRow.rows(from: turnItems)
        var turnRows: [(row: TranscriptRow, itemIndex: Int)] = []
        var itemIndex = turn.items.lowerBound
        for row in rows {
            turnRows.append((row, itemIndex))
            itemIndex += row.itemCount
        }

        var lines: [StandardTranscriptLine] = []
        var summary = state.summary(of: turn)
        // What git saw change, which includes edits made through the shell that no tool reported.
        if let detected = key.detectedFiles { summary.changedFiles = detected }
        // A usage limit shows once, as a card where the work stopped: the agent relaying the
        // provider's message and Native's notice of the failure say the same thing.
        let limitStop = UsageLimitStop(turnItems: state.items[turn.items], stopReason: turn.stopReason)
        if let limitStop {
            turnRows.removeAll { entry in
                if case .item(let item) = entry.row { limitStop.itemIDs.contains(item.id) } else { false }
            }
        }
        // A turn that didn't end normally closes with the reason; the footer says it instead.
        var ending: TranscriptNotice?
        if let reason = turn.stopReason, reason != .endTurn, case .item(.notice(let notice))? = turnRows.last?.row {
            ending = notice
            turnRows.removeLast()
        }

        let folds = key.folding && !key.isLatest && turnRows.count(where: { $0.row.isFoldableActivity }) > 1
        var placedFold = false
        var position = turnRows.startIndex
        while position < turnRows.endIndex {
            let (row, index) = turnRows[position]
            if folds, row.isFoldableActivity {
                if !placedFold {
                    lines.append(Self(id: "fold-\(turn.id)", kind: .fold(turn, summary, isUnfolded: key.isUnfolded)))
                    placedFold = true
                }
                guard key.isUnfolded else {
                    position += 1
                    continue
                }
            }
            if let run = TranscriptActivityRun(rows: turnRows[position...], in: state) {
                lines.append(Self(id: run.id, kind: .activityRun(run)))
                position += run.rowCount
                continue
            }
            lines += Self.lines(for: row, itemIndex: index, in: state)
            position += 1
        }
        if let limitStop {
            lines.append(Self(id: "limit-\(turn.id)", kind: .usageLimit(limitStop, isLatestTurn: key.isLatest)))
        }

        guard !key.isRunning else { return lines }
        let showsChangesCard = key.isLatest && !summary.changedFiles.isEmpty
        if turn.duration != nil || ending != nil || summary.subagents > 0
            || (!showsChangesCard && !summary.changedFiles.isEmpty)
        {
            let subagents = state.items[turn.items].compactMap { item in
                if case .subagent(let subagent) = item { subagent } else { nil }
            }
            lines.append(
                Self(
                    id: "footer-\(turn.id)",
                    kind: .footer(
                        turn, summary, ending: ending, showsChanges: !showsChangesCard, subagents: subagents)))
        }
        if showsChangesCard {
            lines.append(Self(id: "changes-\(turn.id)", kind: .changes(summary)))
        }
        return lines
    }

    /// A row's lines: a line per section of an agent's reply, otherwise the row itself.
    private static func lines(for row: TranscriptRow, itemIndex: Int, in state: SessionState) -> [Self] {
        guard case .item(.message(let message)) = row, message.role == .agent else {
            let thinking = state.thinkingInterval(at: itemIndex).map { ThinkingClock(start: $0.start, end: $0.end) }
            return [Self(id: row.id, kind: .row(row, itemIndex: itemIndex, thinking: thinking))]
        }
        var lines = ReplySections.sections(of: message).enumerated().map { index, section in
            Self(
                id: index == 0 ? row.id : "\(row.id)-\(index)",
                kind: .replySection(section, isFirst: index == 0, itemIndex: itemIndex))
        }
        if !message.attachments.isEmpty {
            if message.text.isEmpty { lines = [] }
            lines.append(
                Self(
                    id: lines.isEmpty ? row.id : "\(row.id)-artifacts",
                    kind: .artifacts(message.attachments, itemIndex: itemIndex)))
        }
        return lines
    }

    private static func spacing(between previous: Self, and next: Self) -> CGFloat {
        switch next.kind {
        // A reply's later sections space themselves, as in the reply as a whole.
        case .replySection(_, isFirst: false, _): 0
        case .footer, .changes, .artifacts: DS.Space.md
        case .row, .replySection, .fold, .activityRun, .usageLimit:
            previous.isDense && next.isDense ? DS.Space.xxs : DS.Space.xl
        }
    }
}

/// Agents' replies in Markdown sections, kept per message so laying out a turn again splits only
/// the reply that changed. Replies only grow, so a reply's length says whether its sections are
/// still current.
private enum ReplySections {
    private static var sections: [UUID: (length: Int, sections: [String])] = [:]
    private static var bytes = 0
    /// Past either limit the cache starts over rather than tracking age. The count covers every
    /// reply of a long session (a 500-turn session has more than 512, which made every layout pass
    /// split every reply again); the byte limit bounds the copies kept.
    private static let capacity = 8192
    private static let byteCapacity = 16 << 20

    static func sections(of message: TranscriptMessage) -> [String] {
        let length = message.text.utf8.count
        if let cached = sections[message.id], cached.length == length {
            return cached.sections
        }
        let split = message.text.markdownSections.map(String.init)
        if sections.count >= capacity || bytes >= byteCapacity {
            sections.removeAll(keepingCapacity: true)
            bytes = 0
        }
        bytes += length - (sections[message.id]?.length ?? 0)
        sections[message.id] = (length, split)
        return split
    }
}
