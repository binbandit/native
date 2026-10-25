import Foundation

extension NativePolicy.DeploymentMode: Codable {}

extension NativePolicy {
    /// How the organization's configuration arrived, and whether Native can trust it at all.
    public struct Deployment: Equatable, Sendable {
        public enum State: String, Equatable, Sendable {
            /// The organization manages nothing, and Native was never enrolled in a restricted mode.
            case absent
            /// Every managed value the organization sets was read and is valid.
            case valid
            /// Something the organization set is malformed. What it set badly is denied.
            case invalid
            /// The organization's configuration can't be read, or disappeared after a restricted
            /// enrollment. Everything optional is denied.
            case unavailable
        }

        /// Why everything optional is denied, whatever the individual keys say.
        public enum Lockdown: String, Equatable, Sendable {
            /// The managed configuration isn't a dictionary.
            case malformed
            /// The managed source, or its deployment mode, can't be read.
            case unavailable
            /// The managed deployment mode isn't one Native knows.
            case invalidMode
            /// A restricted policy disappeared without the organization deploying ordinary mode.
            case removedAfterEnrollment
            /// A restricted policy sets keys this version of Native doesn't know, so it can't honor them.
            case unknownKeys
        }

        public var state = State.absent
        public var lockdown: Lockdown?
        public var revision: PolicyRevision?
        /// The restricted mode the organization last confirmed, while it holds.
        public var enrollment: PolicyEnrollment?
        /// The organization chose the mode (or its absence after enrollment keeps it restricted),
        /// rather than the user's own preference.
        public var isManaged = false

        public init() {}
    }

    public var deploymentMode: DeploymentMode { network.mode }
    /// Internal-only or air-gapped: features are off until the organization allows them and their
    /// enforcement is converted (`PolicyCapability.Enforcement`).
    public var isRestricted: Bool { network.mode != .ordinary }
}

/// Settles the deployment mode before any key, since restricted mode changes how every key resolves.
struct DeploymentResolution {
    var deployment = NativePolicy.Deployment()
    var mode = NativePolicy.DeploymentMode.ordinary
    /// A deployment mode the user set for themselves that isn't one Native knows.
    var userModeIsInvalid = false
    var diagnostics: [PolicyDiagnostic] = []

    init(source: any PolicySource) {
        deployment.revision = PolicyRevision.of(source)
        let enrolled = source.enrollment?.load()
        deployment.enrollment = enrolled
        let key = PolicyKey.deploymentMode.rawValue
        switch source.managedStatus {
        case .malformed:
            lock(.malformed, mode: .airGapped, problem: "managed configuration isn't a dictionary")
        case .unavailable:
            lock(.unavailable, mode: enrolled?.mode ?? .airGapped, problem: "managed configuration can't be read")
        case .available:
            switch source.managedEntry(forKey: key) {
            case .unreadable:
                lock(.unavailable, mode: .airGapped, problem: "can't be read reliably")
            case .value(let raw):
                guard let text = raw as? String, let managed = NativePolicy.DeploymentMode(rawValue: text) else {
                    lock(.invalidMode, mode: .airGapped, problem: "should be ordinary, internalOnly or airGapped")
                    break
                }
                mode = managed
                deployment.isManaged = true
                // The organization's own ordinary mode is the one way out of a restricted enrollment.
                let enrollment =
                    managed == .ordinary ? nil : PolicyEnrollment(mode: managed, revision: deployment.revision)
                source.enrollment?.save(enrollment)
                deployment.enrollment = enrollment
            case .absent:
                if let enrolled {
                    lock(
                        .removedAfterEnrollment, mode: enrolled.mode,
                        problem: "is missing after restricted enrollment; deploy ordinary to leave restricted mode")
                } else if source.managedValue(forKey: PolicyKey.network.rawValue) == nil,
                    let raw = source.userValue(forKey: key)
                {
                    // Someone may restrict their own Native; it never counts as the organization's.
                    if let text = raw as? String, let chosen = NativePolicy.DeploymentMode(rawValue: text) {
                        mode = chosen
                    } else {
                        mode = .airGapped
                        userModeIsInvalid = true
                    }
                }
            }
        }
        if deployment.lockdown == nil, mode != .ordinary, deployment.isManaged, !Self.unknownKeys(in: source).isEmpty {
            lock(.unknownKeys, mode: mode, problem: "restricted mode can't honor policy keys Native doesn't know")
        }
        switch deployment.lockdown {
        case .unavailable?, .removedAfterEnrollment?: deployment.state = .unavailable
        case .some: deployment.state = .invalid
        // The loader settles valid, invalid or absent once it has read every key.
        case nil: break
        }
    }

    var isTrusted: Bool { deployment.lockdown == nil }

    private mutating func lock(
        _ lockdown: NativePolicy.Deployment.Lockdown, mode: NativePolicy.DeploymentMode, problem: String
    ) {
        deployment.lockdown = lockdown
        deployment.isManaged = true
        self.mode = mode
        diagnostics.append(
            PolicyDiagnostic(
                key: PolicyKey.deploymentMode.rawValue, origin: .organization,
                problem: "\(problem); everything optional is denied"))
    }

    /// Managed keys under `policy.` that Native doesn't know, which are usually typos. A source that
    /// can't list its keys reports none.
    static func unknownKeys(in source: any PolicySource) -> [String] {
        let known = Set(PolicyKey.allCases.map(\.rawValue))
        return (source.managedKeys ?? []).filter { $0.hasPrefix(PolicyKey.prefix) && !known.contains($0) }.sorted()
    }
}
