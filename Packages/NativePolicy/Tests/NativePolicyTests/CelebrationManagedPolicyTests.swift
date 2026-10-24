import Testing

@testable import NativePolicy

struct CelebrationManagedPolicyTests {
    @Test func defaultsAndManagedPrecedence() {
        let defaults = PolicyLoader.load(from: StaticPolicySource())
        #expect(defaults.celebrationsEnabled)
        #expect(defaults.organizationName == nil)
        let managed = PolicyLoader.load(
            from: StaticPolicySource(
                managed: ["policy.celebrations.enabled": false, "policy.organization.name": "Northwind Federal IT"],
                user: ["policy.celebrations.enabled": true, "policy.organization.name": "Personal"]))
        #expect(!managed.celebrationsEnabled)
        #expect(managed.organizationName == "Northwind Federal IT")
        #expect(managed.isManaged(.celebrationsEnabled))
    }

    @Test func invalidValuesFallBackWithoutInventingAnOrganization() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: ["policy.celebrations.enabled": "false", "policy.organization.name": "  "],
                user: ["policy.celebrations.enabled": false]))
        #expect(!policy.celebrationsEnabled)
        #expect(policy.organizationName == nil)
        #expect(policy.diagnostics.count == 2)
    }
}
