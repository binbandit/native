import Foundation
import Testing

@testable import NativePolicy

struct CelebrationDownloadPolicyTests {
    @Test func defaultsAllowReleaseDownloads() {
        let policy = PolicyLoader.load(from: StaticPolicySource())
        #expect(policy.celebrations.downloadsEnabled)
        #expect(policy.celebrations.baseURL == nil)
    }

    @Test func managedDisableAndMirrorOverrideUserValues() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: [
                    "policy.celebrations.downloadsEnabled": false,
                    "policy.celebrations.baseURL": "https://mirror.example.com/icons/",
                ],
                user: [
                    "policy.celebrations.downloadsEnabled": true,
                    "policy.celebrations.baseURL": "https://user.example.com/",
                ]))
        #expect(!policy.celebrations.downloadsEnabled)
        #expect(policy.celebrations.baseURL == URL(string: "https://mirror.example.com/icons/"))
        #expect(policy.managedKeys == [.celebrationDownloadsEnabled, .celebrationAssetsBaseURL])
        #expect(policy.diagnostics.isEmpty)
    }

    @Test func invalidValuesReportDiagnosticsAndDenyDownloads() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.celebrations.downloadsEnabled": "yes",
                "policy.celebrations.baseURL": "file:///tmp/icons/",
            ]))
        #expect(policy.diagnostics.count == 2)
        #expect(policy.managedKeys == [.celebrationDownloadsEnabled, .celebrationAssetsBaseURL])
        #expect(!policy.celebrations.downloadsEnabled)
        #expect(policy.celebrations.baseURL == nil)
    }
}
