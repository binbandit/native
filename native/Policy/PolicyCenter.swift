import Foundation
import NativePolicy
import Observation
import os

/// The organization's policy as the app sees it, kept current as managed settings change. Views
/// read it from the environment; models and plugins read `PolicyCenter.shared`, or the center
/// they were given. `policy.inspection` reports every key and capability without their content.
@MainActor
@Observable
final class PolicyCenter {
    static let shared = PolicyCenter()

    /// What Settings says next to anything an organization controls.
    static var managedExplanation: String { shared.policy.managedExplanation }
    static var organizationName: String { shared.policy.organizationDisplayName }
    static var organizationSubject: String { shared.policy.organizationName ?? "Your organization" }
    static var organizationHelp: String { shared.policy.organizationHelp }

    private(set) var policy: NativePolicy

    @ObservationIgnored private let source: any PolicySource
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "Native", category: "Policy")

    init(source: any PolicySource = PolicyCenter.platformSource()) {
        self.source = source
        policy = PolicyLoader.load(from: source)
    }

    /// Follows changes to managed settings; call once, at launch.
    func start() {
        guard watch == nil else { return }
        report(policy)
        watch = Task { [weak self, source] in
            for await policy in PolicyLoader.updates(from: source) {
                self?.apply(policy)
            }
        }
    }

    /// Reads the policy again now, rather than at the next preferences change.
    func reload() {
        apply(PolicyLoader.load(from: source))
    }

    private func apply(_ policy: NativePolicy) {
        guard policy != self.policy else { return }
        self.policy = policy
        report(policy)
    }

    func isManaged(_ key: PolicyKey) -> Bool {
        policy.isManaged(key)
    }

    /// The policy right now, for code that runs before the app has started (plugin set-up).
    nonisolated static func currentPolicy() -> NativePolicy {
        PolicyLoader.load(from: platformSource())
    }

    /// Managed preferences for this platform. A configuration profile can't be installed on a
    /// development Mac without enrolling it, so debug builds can mark keys as managed with
    /// `defaults write <bundle id> policy.debug.managedKeys -array policy.scripts.enabled …`.
    nonisolated static func platformSource() -> any PolicySource {
        #if DEBUG
        let simulated = Set(UserDefaults.standard.stringArray(forKey: "policy.debug.managedKeys") ?? [])
        #else
        let simulated: Set<String> = []
        #endif
        return NativePolicy.platformSource(simulatedManagedKeys: simulated, enrollment: enrollmentStore)
    }

    /// Where a restricted enrollment outlives a restart: a file of Native's own beside its other
    /// data, never a preference (`PolicyEnrollment`). Each isolated instance has its own. Nil for a
    /// process without a bundle id, such as a test harness, which keeps nothing.
    nonisolated static let enrollmentStore: FilePolicyEnrollmentStore? = Bundle.main.bundleIdentifier.map {
        FilePolicyEnrollmentStore(
            url: URL.applicationSupportDirectory.appending(path: "\($0)/Policy", directoryHint: .isDirectory)
                .appending(path: "enrollment.json"))
    }

    /// Diagnostics and the deployment summary never carry values, only keys, states and reasons.
    private func report(_ policy: NativePolicy) {
        let deployment = policy.deployment
        let summary =
            "\(policy.deploymentMode.rawValue), \(deployment.state.rawValue)"
            + (deployment.lockdown.map { ", lockdown \($0.rawValue)" } ?? "")
            + (deployment.revision.map { ", revision \($0)" } ?? "")
        if deployment.lockdown != nil {
            logger.error("Policy \(summary, privacy: .public): everything optional is denied")
        } else if deployment.state != .absent {
            logger.info("Policy \(summary, privacy: .public)")
        }
        for diagnostic in policy.diagnostics {
            logger.error("Policy value \(diagnostic.description, privacy: .public)")
        }
        if !policy.managedKeys.isEmpty {
            let keys = policy.managedKeys.map(\.rawValue).sorted().joined(separator: ", ")
            logger.info("Managed by the organization: \(keys, privacy: .public)")
        }
    }
}
