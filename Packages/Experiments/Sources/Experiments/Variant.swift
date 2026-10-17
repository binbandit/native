/// An experiment that swaps whole implementations: while it's on, each of its claims replaces an
/// extension point's default. A redesign is one variant claiming every point it changes, so it
/// can be promoted, kept as a choice or deleted without touching the default path.
///
///     extension Variant {
///         static let bubbles = Variant(id: "bubbles", title: "Bubbles", summary: "…", stage: .labs,
///             owner: "transcript", reviewBy: …, claims: [Claim(.transcriptStyle, BubbleTranscriptStyle())])
///     }
public struct Variant: ExperimentDeclaration {
    public let descriptor: ExperimentDescriptor

    public init(
        id: ExperimentID,
        title: String,
        summary: String,
        stage: ExperimentStage,
        owner: String,
        reviewBy: ReviewDate,
        requiresRelaunch: Bool = false,
        claims: [Claim]
    ) {
        descriptor = ExperimentDescriptor(
            id: id, title: title, summary: summary, stage: stage, owner: owner, reviewBy: reviewBy,
            requiresRelaunch: requiresRelaunch, tier: .variant(claims: claims)
        )
    }

    public var id: ExperimentID { descriptor.id }
}
