import ACP

/// The standard transcript's lines in two lists: every turn before the latest, and the latest. A
/// reply streaming into the latest turn never changes the earlier turns' lines, so they're shown as
/// a list of their own (`StandardTranscriptLines`) that SwiftUI only looks through again when its
/// version moves. Otherwise every chunk had SwiftUI read the id of each of a long session's
/// thousands of lines.
struct StandardTranscriptPlan {
    let earlier: StandardTranscriptLineList
    let latest: [StandardTranscriptLine]

    var lines: [StandardTranscriptLine] {
        earlier.lines + latest
    }
}

/// Lines, and a version that moves whenever they change.
struct StandardTranscriptLineList {
    let lines: [StandardTranscriptLine]
    let version: Int
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
    /// The latest turn's files as git saw them change (`TurnDetectedChanges`), when known.
    var detectedFiles: [TurnSummary.ChangedFile]?
}

/// Each turn's lines as last laid out, by turn, and the earlier turns' lines put together, held by
/// the transcript that shows them so they go with it. Only the latest version of a turn is kept, so
/// a streaming turn replaces its own entry rather than piling up versions.
final class StandardTranscriptLineCache {
    private var entries: [TranscriptTurn.ID: (key: TurnLinesKey, lines: [StandardTranscriptLine])] = [:]
    /// Past this many turns the cache starts over rather than tracking age.
    private let capacity = 4096
    private var earlier: (keys: ArraySlice<TurnLinesKey>, list: StandardTranscriptLineList)?

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

    /// The lines of the turns `keys` stand for, put together by `make` only when one of them changed.
    func earlierLines(
        for keys: ArraySlice<TurnLinesKey>, make: (ArraySlice<TurnLinesKey>) -> [StandardTranscriptLine]
    ) -> StandardTranscriptLineList {
        if let earlier, earlier.keys == keys {
            return earlier.list
        }
        let list = StandardTranscriptLineList(lines: make(keys), version: (earlier?.list.version ?? 0) + 1)
        earlier = (keys, list)
        return list
    }
}
