import Foundation
import Testing

@testable import NativePolicy

@Suite struct CatalogPolicyTests {
    private func load(managed: [PolicyKey: Any] = [:], user: [PolicyKey: Any] = [:]) -> NativePolicy {
        PolicyLoader.load(
            from: StaticPolicySource(
                managed: Dictionary(uniqueKeysWithValues: managed.map { ($0.key.rawValue, $0.value) }),
                user: Dictionary(uniqueKeysWithValues: user.map { ($0.key.rawValue, $0.value) })))
    }

    @Test func defaultsAllowCatalogWithoutSelectingAnEndpoint() {
        let policy = load()
        #expect(policy == .default)
        #expect(policy.catalog.isEnabled)
        #expect(policy.catalog.indexURL == nil)
        #expect(policy.managedKeys.isEmpty)
        #expect(policy.diagnostics.isEmpty)
    }

    @Test func managedFalseOverridesUserTrue() {
        let policy = load(managed: [.catalogEnabled: false], user: [.catalogEnabled: true])
        #expect(!policy.catalog.isEnabled)
        #expect(policy.catalog.indexURL == nil)
        #expect(policy.managedKeys == [.catalogEnabled])
        #expect(policy.diagnostics.isEmpty)
    }

    @Test func managedMirrorOverridesUserMirrorEvenWhenDisabled() {
        let mirror = "https://catalog.example.com/index.json"
        let policy = load(
            managed: [.catalogEnabled: false, .catalogIndexURL: mirror],
            user: [.catalogEnabled: true, .catalogIndexURL: "https://user.example.com/index.json"])
        #expect(!policy.catalog.isEnabled)
        #expect(policy.catalog.indexURL == URL(string: mirror))
        #expect(policy.managedKeys == [.catalogEnabled, .catalogIndexURL])
        #expect(policy.diagnostics.isEmpty)
    }

    @Test(arguments: [true, false], ["https://mirror.example.com/index.json", "http://mirror.example.com/index.json"])
    func validUserValues(enabled: Bool, mirror: String) {
        let policy = load(user: [.catalogEnabled: enabled, .catalogIndexURL: mirror])
        #expect(policy.catalog.isEnabled == enabled)
        #expect(policy.catalog.indexURL == URL(string: mirror))
        #expect(policy.managedKeys.isEmpty)
        #expect(policy.diagnostics.isEmpty)
    }

    @Test func wrongManagedTypesFailClosedInsteadOfUsingUserValues() {
        let mirror = "https://user.example.com/index.json"
        let policy = load(
            managed: [.catalogEnabled: "true", .catalogIndexURL: [mirror]],
            user: [.catalogEnabled: true, .catalogIndexURL: mirror])
        #expect(!policy.catalog.isEnabled)
        #expect(policy.catalog.indexURL == nil)
        #expect(policy.managedKeys == [.catalogEnabled, .catalogIndexURL])
        #expect(
            policy.diagnostics == [
                PolicyDiagnostic(
                    key: PolicyKey.catalogEnabled.rawValue, origin: .organization,
                    problem: "should be a Boolean; denied"),
                PolicyDiagnostic(
                    key: PolicyKey.catalogIndexURL.rawValue, origin: .organization,
                    problem: "should be an http or https URL; denied"),
            ])
    }

    @Test func wrongUserTypesFallBackToDefaults() {
        let policy = load(user: [.catalogEnabled: "true", .catalogIndexURL: false])
        #expect(policy.catalog == NativePolicy.default.catalog)
        #expect(policy.managedKeys.isEmpty)
        #expect(
            policy.diagnostics == [
                PolicyDiagnostic(
                    key: PolicyKey.catalogEnabled.rawValue, origin: .user, problem: "should be a Boolean; ignored"),
                PolicyDiagnostic(
                    key: PolicyKey.catalogIndexURL.rawValue, origin: .user,
                    problem: "should be an http or https URL; ignored"),
            ])
    }

    @Test(arguments: [
        "", "index.json", "https:index.json", "file:///tmp/index.json", "ftp://mirror.example.com/index.json",
    ])
    func invalidManagedMirrorDisablesTheCatalog(mirror: String) {
        let policy = load(managed: [.catalogIndexURL: mirror], user: [.catalogIndexURL: mirror])
        #expect(policy.catalog.indexURL == nil)
        #expect(!policy.catalog.isEnabled)
        #expect(policy.managedKeys == [.catalogIndexURL])
        #expect(
            policy.diagnostics == [
                PolicyDiagnostic(
                    key: PolicyKey.catalogIndexURL.rawValue, origin: .organization,
                    problem: "should be an http or https URL; denied")
            ])
    }

    @Test func invalidManagedMirrorNeverFallsBackToTheUserMirror() {
        let mirror = "http://user.example.com/index.json"
        let policy = load(managed: [.catalogIndexURL: "file:///tmp/index.json"], user: [.catalogIndexURL: mirror])
        #expect(policy.catalog.indexURL == nil)
        #expect(policy.isManaged(.catalogIndexURL))
        #expect(policy.diagnostics.count == 1)
        #expect(policy.diagnostics.first?.origin == .organization)
    }

    @Test func validManagedValuesDoNotValidateOverriddenUserValues() {
        let policy = load(
            managed: [.catalogEnabled: true, .catalogIndexURL: "http://mirror.example.com/index.json"],
            user: [.catalogEnabled: "no", .catalogIndexURL: "file:///tmp/index.json"])
        #expect(policy.catalog.isEnabled)
        #expect(policy.catalog.indexURL?.scheme == "http")
        #expect(policy.managedKeys == [.catalogEnabled, .catalogIndexURL])
        #expect(policy.diagnostics.isEmpty)
    }

    @Test func catalogKeysAreRecognizedAndTyposStillReported() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.catalog.enabled": true,
                "policy.catalog.indexURL": "https://mirror.example.com/index.json",
                "policy.catalog.indexUrl": "https://typo.example.com/index.json",
            ]))
        #expect(policy.managedKeys == [.catalogEnabled, .catalogIndexURL])
        #expect(
            policy.diagnostics == [
                PolicyDiagnostic(
                    key: "policy.catalog.indexUrl", origin: .organization, problem: "isn't a Native policy key")
            ])
    }

    @Test func catalogAndPluginAllowlistRemainIndependent() {
        let disabled = load(managed: [.catalogEnabled: false])
        #expect(disabled.allowsPlugin("anything"))
        #expect(
            disabled.scriptsEnabled && disabled.labsEnabled && disabled.companionEnabled && disabled.remoteHostsEnabled)
        #expect(disabled.taskScripts == NativePolicy.default.taskScripts)
        #expect(disabled.updates == NativePolicy.default.updates)
        let restricted = load(managed: [.pluginsAllowed: ["internal-plugin"]])
        #expect(restricted.catalog == NativePolicy.default.catalog)
        #expect(restricted.allowsPlugin("internal-plugin"))
        #expect(!restricted.allowsPlugin("other"))
    }
}
