import Foundation
import NativePolicy
import Observation
import os

/// The organization's policy as the app sees it, kept current as managed settings change. Views
/// read it from the environment; models and plugins read `PolicyCenter.shared`.
@MainActor
@Observable
final class PolicyCenter {
    static let shared = PolicyCenter()

    /// What Settings says next to anything an organization controls.
    static let managedExplanation = "Managed by your organization"

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
                guard let self, policy != self.policy else { continue }
                self.policy = policy
                self.report(policy)
            }
        }
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
        return NativePolicy.platformSource(simulatedManagedKeys: simulated)
    }

    private func report(_ policy: NativePolicy) {
        for diagnostic in policy.diagnostics {
            logger.error("Ignored policy value \(diagnostic.description, privacy: .public)")
        }
        if !policy.managedKeys.isEmpty {
            let keys = policy.managedKeys.map(\.rawValue).sorted().joined(separator: ", ")
            logger.info("Managed by the organization: \(keys, privacy: .public)")
        }
    }
}
