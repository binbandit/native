/// The simplest experiment: a declared on/off point, read at exactly one call site. Reading it is
/// the one place an experiment may be a plain `if`, because the declaration names that site.
///
///     extension Gate {
///         static let unfoldExploration = Gate(id: "unfold-exploration", title: "…", summary: "…",
///             site: "Transcript ▸ tool activity", stage: .labs, owner: "transcript",
///             reviewBy: ReviewDate(year: 2027, month: 1, day: 31))
///     }
public struct Gate: ExperimentDeclaration {
    public let descriptor: ExperimentDescriptor
    public let defaultValue: Bool

    /// - Parameter site: The one place that reads the gate, as Labs should name it.
    public init(
        id: ExperimentID,
        title: String,
        summary: String,
        site: String,
        stage: ExperimentStage,
        owner: String,
        reviewBy: ReviewDate,
        requiresRelaunch: Bool = false,
        default defaultValue: Bool = false
    ) {
        self.defaultValue = defaultValue
        descriptor = ExperimentDescriptor(
            id: id, title: title, summary: summary, stage: stage, owner: owner, reviewBy: reviewBy,
            requiresRelaunch: requiresRelaunch, tier: .gate(defaultValue: defaultValue, site: site)
        )
    }

    public var id: ExperimentID { descriptor.id }

    func value(from stored: StoredValue?) -> Bool {
        stored.flatMap(Bool.init(stored:)) ?? defaultValue
    }
}
