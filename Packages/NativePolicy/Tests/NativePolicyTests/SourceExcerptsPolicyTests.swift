import Testing

@testable import NativePolicy

@Suite struct SourceExcerptsPolicyTests {
    @Test func ordinaryAllowsButRestrictedRequiresManagedGrants() {
        let ordinary = PolicyLoader.load(from: StaticPolicySource())
        #expect(ordinary.sourceExcerptsSendingEnabled)
        #expect(ordinary.sourceExcerptsRetentionEnabled)
        let restricted = PolicyLoader.load(
            from: StaticPolicySource(managed: ["policy.deployment.mode": "internalOnly"]))
        #expect(!restricted.sourceExcerptsSendingEnabled)
        #expect(!restricted.sourceExcerptsRetentionEnabled)
    }

    @Test func sendingAndRetentionAreIndependentAndMalformedValuesDeny() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.sourceExcerpts.sendingEnabled": false,
                "policy.sourceExcerpts.retentionEnabled": true,
            ]))
        #expect(!policy.sourceExcerptsSendingEnabled)
        #expect(policy.sourceExcerptsRetentionEnabled)
        let invalid = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.sourceExcerpts.sendingEnabled": "invalid",
                "policy.sourceExcerpts.retentionEnabled": "invalid",
            ]))
        #expect(!invalid.sourceExcerptsSendingEnabled)
        #expect(!invalid.sourceExcerptsRetentionEnabled)
    }
}
