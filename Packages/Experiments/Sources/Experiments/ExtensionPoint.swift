/// Names an extension point. It's also how claims find their point, so it never changes.
public struct ExtensionPointID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }
}

/// A seam where Native's behavior can be swapped: a contract (a protocol) and the implementation
/// used when nothing replaces it. Experiments (and later plugins) contribute alternatives; the
/// resolver picks the one in effect. Contracts that aren't about views (a queue policy, a title
/// strategy) are plain Swift, so engines outside the UI resolve them the same way.
///
///     protocol TranscriptStyle: Sendable { … }
///     extension ExtensionPoint where Contract == any TranscriptStyle {
///         static var transcriptStyle: Self {
///             Self(id: "transcript.style", title: "Transcript style", default: StandardTranscriptStyle())
///         }
///     }
public struct ExtensionPoint<Contract: Sendable>: Sendable {
    public let id: ExtensionPointID
    /// How Labs names it, e.g. "Transcript style".
    public let title: String
    public let defaultImplementation: Contract

    public init(id: ExtensionPointID, title: String, default defaultImplementation: Contract) {
        self.id = id
        self.title = title
        self.defaultImplementation = defaultImplementation
    }
}

/// An implementation for one extension point. It's typed where it's made, so it always fits the
/// point it claims.
public struct Claim: Sendable {
    public let point: ExtensionPointID
    public let pointTitle: String
    private let implementation: any Sendable

    public init<Contract>(_ point: ExtensionPoint<Contract>, _ implementation: Contract) {
        self.point = point.id
        pointTitle = point.title
        self.implementation = implementation
    }

    func implementation<Contract>(for point: ExtensionPoint<Contract>) -> Contract? {
        guard point.id == self.point else { return nil }
        return implementation as? Contract
    }
}

/// Where a contributed implementation comes from. Plugins become a second case when they can
/// contribute implementations; resolution treats every source alike.
public enum ContributionSource: Hashable, Sendable {
    case experiment(ExperimentID)
}

/// A claim from a source that's in effect.
public struct Contribution: Sendable {
    public let source: ContributionSource
    public let claim: Claim

    public init(source: ContributionSource, claim: Claim) {
        self.source = source
        self.claim = claim
    }
}

/// Two or more sources claiming the same extension point at once. Neither wins: the point falls
/// back to its default until the user turns one off, so the result never depends on order.
public struct ExtensionConflict: Hashable, Sendable {
    public let point: ExtensionPointID
    public let pointTitle: String
    /// In catalog order.
    public let sources: [ContributionSource]
}

/// Which implementation each extension point uses, given the contributions in effect.
public struct ExtensionResolver: Sendable {
    /// How a point was resolved.
    public enum Outcome: Hashable, Sendable {
        case standard
        case contributed(by: ContributionSource)
        case conflict(ExtensionConflict)
    }

    public let contributions: [Contribution]

    public init(contributions: [Contribution]) {
        self.contributions = contributions
    }

    public func implementation<Contract>(of point: ExtensionPoint<Contract>) -> Contract {
        let claims = contributions.filter { $0.claim.point == point.id }
        guard claims.count == 1, let implementation = claims[0].claim.implementation(for: point) else {
            return point.defaultImplementation
        }
        return implementation
    }

    public func outcome(for point: ExtensionPointID) -> Outcome {
        let claims = contributions.filter { $0.claim.point == point }
        switch claims.count {
        case 0: return .standard
        case 1: return .contributed(by: claims[0].source)
        default: return .conflict(ExtensionConflict(point: point, pointTitle: claims[0].claim.pointTitle, sources: claims.map(\.source)))
        }
    }

    /// Every point claimed more than once, in the order the points were first claimed.
    public var conflicts: [ExtensionConflict] {
        var seen: Set<ExtensionPointID> = []
        return contributions.compactMap { contribution in
            let point = contribution.claim.point
            guard seen.insert(point).inserted, case .conflict(let conflict) = outcome(for: point) else { return nil }
            return conflict
        }
    }
}
