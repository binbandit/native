/// Original transcript membership survives presentation-only polling folds. Item indices track
/// each visible item's position; source indices also include polls folded into its command.
public struct TranscriptRowSource: Hashable, Sendable {
    public let row: TranscriptRow
    public let itemIndices: [Int]
    public let sourceIndices: Set<Int>

    init(row: TranscriptRow, itemIndices: [Int], sourceIndices: Set<Int>) {
        self.row = row
        self.itemIndices = itemIndices
        self.sourceIndices = sourceIndices
    }
}
