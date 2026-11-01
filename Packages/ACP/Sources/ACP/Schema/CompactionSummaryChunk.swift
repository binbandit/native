/// A streamed part of the summary retained by a context compaction.
public struct CompactionSummaryChunk: Decodable, Sendable {
    public var compactionId: String
    public var content: ContentBlock
}
