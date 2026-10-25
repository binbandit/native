import Foundation

/// How one key's effective value came about.
public struct PolicyKeyStatus: Equatable, Sendable {
    /// The organization's entry for the key.
    public enum Validity: String, Equatable, Sendable {
        case absent, valid, invalid
        /// Set, but unreadable, or the whole managed source can't be trusted.
        case unavailable

        /// The organization set something Native couldn't use, so the key failed closed.
        public var isFailure: Bool { self == .invalid || self == .unavailable }
    }

    /// Where the effective value came from.
    public enum Origin: String, Equatable, Sendable {
        case organization
        case user
        /// Native's ordinary default.
        case `default`
        /// Restricted mode's value: unmanaged keys, and grants for capabilities not converted yet.
        case restricted
        /// The organization's entry was unusable, so the most restrictive value applies.
        case failClosed
    }

    public var validity: Validity
    public var origin: Origin

    public init(validity: Validity, origin: Origin) {
        self.validity = validity
        self.origin = origin
    }

    static let ordinaryDefault = PolicyKeyStatus(validity: .absent, origin: .default)
}

/// Applies the precedence. Ordinary mode: the organization's value, then the user's, then Native's
/// default. Restricted mode: the organization's value, or the restricted value; user values never
/// apply. A managed value Native can't use never falls through to a more permissive one: the key
/// takes its fail-closed value, in every mode.
struct PolicyResolver {
    let source: any PolicySource
    let isRestricted: Bool
    /// False under a deployment lockdown: every key takes its fail-closed value.
    let isTrusted: Bool
    /// Every key that didn't take Native's ordinary default.
    private(set) var statuses: [PolicyKey: PolicyKeyStatus] = [:]
    private(set) var diagnostics: [PolicyDiagnostic] = []

    init(source: any PolicySource, isRestricted: Bool, isTrusted: Bool) {
        self.source = source
        self.isRestricted = isRestricted
        self.isTrusted = isTrusted
    }

    /// `restricted` is the value restricted mode uses when the organization doesn't grant more;
    /// `invalid`, when given, is a stricter value for a managed entry Native can't use.
    mutating func resolve<Value>(
        _ key: PolicyKey, expecting expected: String, ordinary: Value, restricted: Value, invalid: Value? = nil,
        _ parse: (Any, inout [String]) -> Value?
    ) -> Value {
        let failClosed = invalid ?? restricted
        let entry = source.managedEntry(forKey: key.rawValue)
        guard isTrusted else {
            let isAbsent = if case .absent = entry { true } else { false }
            statuses[key] = PolicyKeyStatus(validity: isAbsent ? .absent : .unavailable, origin: .failClosed)
            return failClosed
        }
        switch entry {
        case .unreadable:
            statuses[key] = PolicyKeyStatus(validity: .unavailable, origin: .failClosed)
            report(key, .organization, "can't be read reliably; denied")
            return failClosed
        case .value(let raw):
            var problems: [String] = []
            let value = parse(raw, &problems)
            guard let value, !isRestricted || problems.isEmpty else {
                statuses[key] = PolicyKeyStatus(validity: .invalid, origin: .failClosed)
                if value == nil {
                    report(key, .organization, "should be \(expected); denied")
                    problems.forEach { report(key, .organization, $0) }
                } else {
                    // Restricted mode never keeps the usable part of a collection.
                    report(key, .organization, "has \(problems.count) unusable entries; denied")
                }
                return failClosed
            }
            problems.forEach { report(key, .organization, $0) }
            if isRestricted && key.grantsOnlyUnconverted {
                statuses[key] = PolicyKeyStatus(validity: .valid, origin: .restricted)
                return restricted
            }
            statuses[key] = PolicyKeyStatus(validity: .valid, origin: .organization)
            return value
        case .absent:
            if isRestricted {
                statuses[key] = PolicyKeyStatus(validity: .absent, origin: .restricted)
                return restricted
            }
            if let raw = source.userValue(forKey: key.rawValue) {
                var problems: [String] = []
                if let value = parse(raw, &problems) {
                    problems.forEach { report(key, .user, $0) }
                    statuses[key] = PolicyKeyStatus(validity: .absent, origin: .user)
                    return value
                }
                report(key, .user, "should be \(expected); ignored")
            }
            return ordinary
        }
    }

    private mutating func report(_ key: PolicyKey, _ origin: PolicyDiagnostic.Origin, _ problem: String) {
        diagnostics.append(PolicyDiagnostic(key: key.rawValue, origin: origin, problem: problem))
    }
}
