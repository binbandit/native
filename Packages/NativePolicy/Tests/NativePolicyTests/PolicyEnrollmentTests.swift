import Foundation
import Testing

@testable import NativePolicy

/// A restricted mode the organization deployed outlives its profile, and only its own ordinary mode
/// releases it.
@Suite struct PolicyEnrollmentTests {
    private func load(
        managed: [String: Any] = [:], user: [String: Any] = [:], enrollment: any PolicyEnrollmentStore
    )
        -> NativePolicy
    {
        PolicyLoader.load(from: StaticPolicySource(managed: managed, user: user, enrollment: enrollment))
    }

    private func internalOnly(_ extra: [String: Any] = [:]) -> [String: Any] {
        extra.merging(["policy.deployment.mode": "internalOnly"]) { $1 }
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PolicyEnrollmentTests-\(UUID().uuidString)")
    }

    @Test func removingARestrictedProfileKeepsItRestrictedUntilTheOrganizationSaysOrdinary() {
        let store = MemoryPolicyEnrollmentStore()
        let enrolled = load(managed: internalOnly(["policy.plugins.allowed": ["acme"]]), enrollment: store)
        #expect(enrolled.deployment.state == .valid && enrolled.isRestricted)
        #expect(store.load()?.mode == .internalOnly && store.load()?.revision == enrolled.deployment.revision)

        // The profile is removed, and Native restarts with only the user's own preferences.
        let removed = load(
            user: ["policy.deployment.mode": "ordinary", "policy.plugins.allowed": ["acme"]], enrollment: store)
        #expect(removed.deployment.lockdown == .removedAfterEnrollment && removed.deployment.state == .unavailable)
        #expect(removed.deploymentMode == .internalOnly && removed.allowedPlugins == [])
        #expect(removed.decision(for: .pluginAppearance) == .disabled(.policyUnavailable))

        // A replacement profile without the mode is still not the organization's way out.
        let partial = load(managed: ["policy.plugins.allowed": ["acme"]], enrollment: store)
        #expect(partial.deployment.lockdown == .removedAfterEnrollment)

        let released = load(managed: ["policy.deployment.mode": "ordinary"], enrollment: store)
        #expect(released.deployment.lockdown == nil && !released.isRestricted)
        #expect(store.load() == nil)
        #expect(!load(enrollment: store).isRestricted)
    }

    @Test func enrollmentFileSurvivesARestartAndAnUnreadableOneStaysRestricted() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Policy/enrollment.json")
        _ = load(managed: ["policy.deployment.mode": "airGapped"], enrollment: FilePolicyEnrollmentStore(url: url))
        let restarted = load(enrollment: FilePolicyEnrollmentStore(url: url))
        #expect(restarted.deploymentMode == .airGapped && restarted.deployment.lockdown == .removedAfterEnrollment)

        try Data("not json".utf8).write(to: url)
        #expect(FilePolicyEnrollmentStore(url: url).load()?.mode == .airGapped)
        _ = load(managed: ["policy.deployment.mode": "ordinary"], enrollment: FilePolicyEnrollmentStore(url: url))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func aRestrictionThatCantBeWrittenStillHoldsAndSaysSo() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The enrollment's folder is a file, so the record can't be written.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "Policy"))
        let store = FilePolicyEnrollmentStore(url: folder.appending(path: "Policy/enrollment.json"))

        let enrolled = load(managed: ["policy.deployment.mode": "airGapped"], enrollment: store)
        #expect(enrolled.deploymentMode == .airGapped && enrolled.deployment.state == .valid)
        #expect(
            enrolled.diagnostics.map(\.problem).contains(
                "restricted mode couldn't be recorded; it holds until Native quits"))

        let removed = load(enrollment: store)
        #expect(removed.deploymentMode == .airGapped && removed.deployment.lockdown == .removedAfterEnrollment)

        let released = load(managed: ["policy.deployment.mode": "ordinary"], enrollment: store)
        #expect(!released.isRestricted && !load(enrollment: store).isRestricted)
    }
}
