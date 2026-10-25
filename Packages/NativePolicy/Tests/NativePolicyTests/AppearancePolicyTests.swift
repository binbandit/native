import CodeThemeCatalog
import Testing

@testable import NativePolicy

@Suite struct AppearancePolicyTests {
    @Test(arguments: CodeTheme.all.map(\.id.rawValue))
    func acceptsBuiltInThemes(_ id: String) {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.appearance.codeTheme": id,
                "policy.appearance.codeTheme.reason": "Consistent code colors.",
                "policy.organization.name": "Northwind Federal IT",
                "policy.organization.contact": "#it-help",
            ]))
        #expect(policy.appearanceCodeTheme == id)
        #expect(policy.appearanceCodeThemeReason == "Consistent code colors.")
        #expect(policy.organizationName == "Northwind Federal IT")
        #expect(policy.organizationContact == "#it-help")
        #expect(policy.isManaged(.appearanceCodeTheme))
        #expect(policy.diagnostics.isEmpty)
    }

    @Test(arguments: ["missing", "", "lantern.dusk"])
    func rejectsUnknownIDs(_ id: String) {
        let policy = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.appearance.codeTheme": id]))
        #expect(policy.appearanceCodeTheme == nil)
        // The organization set it badly: reported, and the user's own theme stays.
        #expect(policy.keyStatus[.appearanceCodeTheme] == PolicyKeyStatus(validity: .invalid, origin: .failClosed))
        #expect(policy.diagnostics.count == 1)
        #expect(policy.diagnostics.first?.key == "policy.appearance.codeTheme")
    }

    @Test func removalRestoresAbsenceAndInvalidMetadataIsReported() {
        let empty = PolicyLoader.load(from: StaticPolicySource())
        #expect(empty.appearanceCodeTheme == nil)
        let invalid = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.appearance.codeTheme": 12,
                "policy.appearance.codeTheme.reason": true,
                "policy.organization.name": " ",
                "policy.organization.contact": [],
            ]))
        #expect(invalid.diagnostics.count == 4)
    }
}
