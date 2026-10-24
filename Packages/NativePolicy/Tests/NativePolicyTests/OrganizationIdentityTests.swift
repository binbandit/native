import Testing

@testable import NativePolicy

struct OrganizationIdentityTests {
    @Test func identityAndContactUsePolicyPrecedence() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: [
                    "policy.organization.name": " Northwind Federal IT ", "policy.organization.contact": " #it-help ",
                ],
                user: ["policy.organization.name": "Personal", "policy.organization.contact": "elsewhere"]))
        #expect(policy.organizationDisplayName == "Northwind Federal IT")
        #expect(policy.organizationHelp == "Ask in #it-help.")
        #expect(policy.isManaged(.organizationContact))
    }

    @Test func missingAndInvalidIdentityStayHonest() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: ["policy.organization.contact": " ", "policy.organization.name": 42]))
        #expect(policy.organizationDisplayName == "your organization")
        #expect(policy.organizationHelp == "Ask your administrator.")
        #expect(policy.diagnostics.count == 2)
    }
}
