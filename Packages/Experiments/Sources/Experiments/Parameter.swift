/// A typed value an experiment tunes, such as a threshold or a default behavior, with the values it
/// allows. A saved value outside them reads as the default.
///
///     extension Parameter where Value == TranscriptWidth {
///         static var transcriptWidth: Self {
///             Self(id: "transcript-width", title: "…", summary: "…", site: "Session ▸ column width",
///                  stage: .beta, owner: "transcript", reviewBy: …, default: .standard, domain: .allCases)
///         }
///     }
public struct Parameter<Value: ParameterValue>: ExperimentDeclaration {
    public let descriptor: ExperimentDescriptor
    public let defaultValue: Value
    public let domain: ParameterDomain<Value>

    /// - Parameter site: Where the value is read, as Labs should name it.
    public init(
        id: ExperimentID,
        title: String,
        summary: String,
        site: String,
        stage: ExperimentStage,
        owner: String,
        reviewBy: ReviewDate,
        requiresRelaunch: Bool = false,
        default defaultValue: Value,
        domain: ParameterDomain<Value>
    ) {
        self.defaultValue = defaultValue
        self.domain = domain
        let spec = ParameterSpec(defaultValue: defaultValue.stored, input: domain.input, site: site)
        descriptor = ExperimentDescriptor(
            id: id, title: title, summary: summary, stage: stage, owner: owner, reviewBy: reviewBy,
            requiresRelaunch: requiresRelaunch, tier: .parameter(spec)
        )
    }

    public var id: ExperimentID { descriptor.id }

    func value(from stored: StoredValue?) -> Value {
        guard let stored, descriptor.accepts(stored), let value = Value(stored: stored) else { return defaultValue }
        return value
    }
}

/// The values a parameter allows.
public struct ParameterDomain<Value: ParameterValue>: Sendable {
    let input: ParameterSpec.Input

    private init(input: ParameterSpec.Input) {
        self.input = input
    }

    /// Exactly these values, each with the title Labs shows for it.
    public static func options(_ options: [(value: Value, title: String)]) -> Self {
        Self(input: .options(options.map { ParameterSpec.Option(value: $0.value.stored, title: $0.title) }))
    }
}

extension ParameterDomain where Value: ParameterChoice {
    /// Every case, in declaration order.
    public static var allCases: Self {
        .options(Value.allCases.map { (value: $0, title: $0.title) })
    }
}

extension ParameterDomain where Value == Int {
    /// Whole numbers from `range`'s lower bound, `step` apart.
    public static func range(_ range: ClosedRange<Int>, step: Int = 1, title: (Int) -> String = { "\($0)" }) -> Self {
        .options(stride(from: range.lowerBound, through: range.upperBound, by: max(step, 1)).map { ($0, title($0)) })
    }
}

extension ParameterDomain where Value == Double {
    /// Numbers from `range`'s lower bound, `step` apart.
    public static func range(_ range: ClosedRange<Double>, step: Double, title: (Double) -> String) -> Self {
        let values =
            step > 0 ? Array(stride(from: range.lowerBound, through: range.upperBound, by: step)) : [range.lowerBound]
        return .options(values.map { ($0, title($0)) })
    }
}

extension ParameterDomain where Value == String {
    /// Any text the user types.
    public static func text(placeholder: String) -> Self {
        Self(input: .text(placeholder: placeholder))
    }
}

/// A parameter's default and allowed values with their types erased, for Labs and storage.
public struct ParameterSpec: Sendable {
    public enum Input: Sendable {
        case options([Option])
        case text(placeholder: String)
    }

    public struct Option: Hashable, Sendable {
        public let value: StoredValue
        public let title: String
    }

    public let defaultValue: StoredValue
    public let input: Input
    /// Where the value is read.
    public let site: String

    func accepts(_ value: StoredValue) -> Bool {
        switch input {
        case .options(let options): options.contains { $0.value == value }
        case .text: value.kind == .string
        }
    }
}
