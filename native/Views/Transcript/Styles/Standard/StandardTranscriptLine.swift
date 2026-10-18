import ACP
import SwiftUI

/// One line of the standard transcript: a row, an earlier turn's folded tool work, a finished
/// turn's footer, or the files-changed card after the latest turn.
struct StandardTranscriptLine: Identifiable {
    enum Kind {
        /// A transcript row and the index of its first item, which times reasoning.
        case row(TranscriptRow, itemIndex: Int)
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

    /// Tool work reads as one dense block, Factory style; everything else gets room to breathe.
    private var isDense: Bool {
        switch kind {
        case .row(let row, _): row.isToolActivity
        case .fold: true
        case .footer, .changes, .usageLimit: false
        }
    }

    /// Lays out `transcript` turn by turn. With `folding` on, every turn but the latest folds its
    /// tool work into one line (unless the user opened it), and each finished turn closes with a
    /// footer; the latest closes with its changes, once it's done.
    static func plan(
        _ transcript: TranscriptStyleConfiguration, folding: Bool, unfolded: Set<TranscriptTurn.ID>
    ) -> [StandardTranscriptLine] {
        let state = transcript.session.state
        let turns = state.turns
        var lines: [StandardTranscriptLine] = []
        var rows = transcript.rows[...]
        var itemIndex = 0

        for (position, turn) in turns.enumerated() {
            var turnRows: [(row: TranscriptRow, itemIndex: Int)] = []
            while let row = rows.first, itemIndex < turn.items.upperBound {
                turnRows.append((row, itemIndex))
                itemIndex += row.itemCount
                rows = rows.dropFirst()
            }

            let isLatest = position == turns.count - 1
            let isRunning = isLatest && transcript.isWorking
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

            let folds = folding && !isLatest && turnRows.count(where: { $0.row.isFoldableActivity }) > 1
            let isUnfolded = unfolded.contains(turn.id)
            var placedFold = false
            for (row, index) in turnRows {
                if folds, row.isFoldableActivity {
                    if !placedFold {
                        lines.append(Self(id: "fold-\(turn.id)", kind: .fold(turn, summary, isUnfolded: isUnfolded)))
                        placedFold = true
                    }
                    guard isUnfolded else { continue }
                }
                lines.append(Self(id: row.id, kind: .row(row, itemIndex: index)))
            }
            if let limitStop {
                lines.append(Self(id: "limit-\(turn.id)", kind: .usageLimit(limitStop, isLatestTurn: isLatest)))
            }

            guard !isRunning else { continue }
            let showsChangesCard = isLatest && !summary.changedFiles.isEmpty
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
        }
        // Rows past the last turn can't happen (every item is in a turn), but never drop any.
        lines += rows.map { Self(id: $0.id, kind: .row($0, itemIndex: itemIndex)) }

        for index in lines.indices.dropFirst() {
            lines[index].spacing = spacing(between: lines[index - 1], and: lines[index])
        }
        return lines
    }

    private static func spacing(between previous: Self, and next: Self) -> CGFloat {
        switch next.kind {
        case .footer, .changes: DS.Space.md
        case .row, .fold, .usageLimit: previous.isDense && next.isDense ? DS.Space.xxs : DS.Space.xl
        }
    }
}
