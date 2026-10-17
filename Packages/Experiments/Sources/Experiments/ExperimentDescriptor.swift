/// What every experiment declares, whatever its tier: what it is, how far along, who owns it, when
/// to review it and what it changes. Labs shows all of it.
public struct ExperimentDescriptor: Identifiable, Sendable {
    /// The three kinds of experiment, from a switch at one call site to a swapped implementation.
    public enum Tier: Sendable {
        /// On or off, read at exactly one call site.
        case gate(defaultValue: Bool, site: String)
        /// A typed value with a default and the values it allows.
        case parameter(ParameterSpec)
        /// Alternative implementations for extension points, used while the experiment is on.
        case variant(claims: [Claim])
    }

    public let id: ExperimentID
    public let title: String
    /// One line on what changes when it's on.
    public let summary: String
    public let stage: ExperimentStage
    /// Who decides what happens to it: a person, team or area such as "transcript".
    public let owner: String
    public let reviewBy: ReviewDate
    /// Whether a change takes effect only the next time the app opens.
    public let requiresRelaunch: Bool
    public let tier: Tier

    /// The gates, parameters and extension points it changes.
    public var touches: [TouchPoint] {
        switch tier {
        case .gate(_, let site): [TouchPoint(kind: .gate, title: site)]
        case .parameter(let spec): [TouchPoint(kind: .parameter, title: spec.site)]
        case .variant(let claims): claims.map { TouchPoint(kind: .extensionPoint, title: $0.pointTitle) }
        }
    }

    /// The value in effect when the user hasn't changed it. Variants are opt-in, so they start off.
    public var defaultValue: StoredValue {
        switch tier {
        case .gate(let defaultValue, _): .bool(defaultValue)
        case .parameter(let spec): spec.defaultValue
        case .variant: .bool(false)
        }
    }

    /// Whether `value` is one this experiment can hold. Anything else (a value saved by a build
    /// that allowed more) reads as the default.
    public func accepts(_ value: StoredValue) -> Bool {
        switch tier {
        case .gate, .variant: value.kind == .bool
        case .parameter(let spec): spec.accepts(value)
        }
    }
}

/// Something an experiment changes, for Labs to name.
public struct TouchPoint: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case gate, parameter, extensionPoint
    }

    public let kind: Kind
    /// Where it is, such as "Transcript ▸ tool activity" or "Transcript style".
    public let title: String
}

/// A type that declares one experiment: a `Gate`, a `Parameter` or a `Variant`.
public protocol ExperimentDeclaration: Sendable {
    var descriptor: ExperimentDescriptor { get }
}
