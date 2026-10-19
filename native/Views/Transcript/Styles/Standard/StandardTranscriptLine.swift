import ACP
import SwiftUI

/// One line of the standard transcript: a row, a long run of tool work condensed into one list,
/// an earlier turn's folded tool work, a finished turn's footer, or the files-changed card after
/// the latest turn.
struct StandardTranscriptLine: Identifiable {
    enum Kind {
        /// A transcript row and the index of its first item, which times reasoning.
        case row(TranscriptRow, itemIndex: Int)
        /// A section of an agent's reply (`String.markdownSections`), the reply being the item at
        /// `itemIndex`. A long reply is a line per section, so the lazy stack lays out and draws only
        /// the sections on screen, and while it streams only the last one changes.
        case replySection(String, isFirst: Bool, itemIndex: Int)
        /// More tool calls in a row than fit on screen, as one condensed list (`ToolRunView`).
        case activityRun(TranscriptActivityRun)
        /// An earlier turn's tool work as one line ("Explored 6 files, edited 3 files").
        case fold(TranscriptTurn, TurnSummary, isUnfolded: Bool)
        /// How a finished turn went: how it ended, how long it took, what it changed, its agents.
        case footer(TranscriptTurn, TurnSummary, ending: TranscriptNotice?, showsChanges: Bool)
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
        case .row(let row, _): row.isToolActivity
        case .fold, .activityRun: true
        case .replySection, .footer, .changes, .usageLimit: false
        }
    }

    /// Lays out `transcript` turn by turn. With `folding` on, every turn but the latest folds its
    /// tool work into one line (unless the user opened it), and each finished turn closes with a
    /// footer; the latest closes with its changes, once it's done.
    ///
    /// This runs on every update, and a long session has hundreds of turns, so each turn's lines are
    /// kept until the turn changes (`TranscriptTurn.revision`) and only the turn that changed is laid
    /// out again.
    static func plan(
        _ transcript: TranscriptStyleConfiguration, folding: Bool, unfolded: Set<TranscriptTurn.ID>,
        cache: StandardTranscriptLineCache
    ) -> [StandardTranscriptLine] {
        let state = transcript.session.state
        let turns = state.turns
        var lines: [StandardTranscriptLine] = []
        for (position, turn) in turns.enumerated() {
            let isLatest = position == turns.count - 1
            let key = TurnLinesKey(
                turn: turn, folding: folding, isUnfolded: unfolded.contains(turn.id), isLatest: isLatest,
                isRunning: isLatest && transcript.isWorking, unfoldsExploration: transcript.unfoldsExploration)
            lines += cache.lines(for: key) { Self.lines(for: key, in: state) }
        }
        for index in lines.indices.dropFirst() {
            lines[index].spacing = spacing(between: lines[index - 1], and: lines[index])
        }
        return lines
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
        let summary = state.summary(of: turn)
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
            lines += Self.lines(for: row, itemIndex: index)
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
            lines.append(
                Self(
                    id: "footer-\(turn.id)",
                    kind: .footer(turn, summary, ending: ending, showsChanges: !showsChangesCard)))
        }
        if showsChangesCard {
            lines.append(Self(id: "changes-\(turn.id)", kind: .changes(summary)))
        }
        return lines
    }

    /// A row's lines: a line per section of an agent's reply, otherwise the row itself.
    private static func lines(for row: TranscriptRow, itemIndex: Int) -> [Self] {
        guard case .item(.message(let message)) = row, message.role == .agent else {
            return [Self(id: row.id, kind: .row(row, itemIndex: itemIndex))]
        }
        return ReplySections.sections(of: message).enumerated().map { index, section in
            Self(
                id: index == 0 ? row.id : "\(row.id)-\(index)",
                kind: .replySection(section, isFirst: index == 0, itemIndex: itemIndex))
        }
    }

    private static func spacing(between previous: Self, and next: Self) -> CGFloat {
        switch next.kind {
        // A reply's later sections space themselves, as in the reply as a whole.
        case .replySection(_, isFirst: false, _): 0
        case .footer, .changes: DS.Space.md
        case .row, .replySection, .fold, .activityRun, .usageLimit:
            previous.isDense && next.isDense ? DS.Space.xxs : DS.Space.xl
        }
    }
}

/// Everything a turn's lines depend on. The turn carries its revision, which goes up whenever one
/// of its items changes, and its clock, which changes as it ends.
struct TurnLinesKey: Hashable {
    let turn: TranscriptTurn
    let folding: Bool
    let isUnfolded: Bool
    let isLatest: Bool
    let isRunning: Bool
    let unfoldsExploration: Bool
}

/// Each turn's lines as last laid out, by turn, held by the transcript that shows them so they go
/// with it. Only the latest version of a turn is kept, so a streaming turn replaces its own entry
/// rather than piling up versions.
final class StandardTranscriptLineCache {
    private var entries: [TranscriptTurn.ID: (key: TurnLinesKey, lines: [StandardTranscriptLine])] = [:]
    /// Past this many turns the cache starts over rather than tracking age.
    private let capacity = 4096

    func lines(for key: TurnLinesKey, make: () -> [StandardTranscriptLine]) -> [StandardTranscriptLine] {
        if let entry = entries[key.turn.id], entry.key == key {
            return entry.lines
        }
        let lines = make()
        if entries.count >= capacity {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key.turn.id] = (key, lines)
        return lines
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
