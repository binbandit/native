import Foundation
import Testing

@testable import NativePolicy

@Suite struct NetworkPolicyTests {
    @Test func ordinaryDefaultsAndManagedDenial() {
        #expect(PolicyLoader.load(from: StaticPolicySource()).network == NativePolicy.Network())
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: ["policy.network": ["services": ["icons.assets": ["enabled": false]]]],
                user: ["policy.network": ["services": ["icons.assets": ["enabled": true]]]]))
        #expect(policy.network.services[.iconAssets]?.enabled == false)
        #expect(policy.isManaged(.network))
    }

    @Test func malformedManagedModeCannotFallBack() {
        for raw: Any in ["airgap", "", 1, true, ["ordinary"]] {
            let policy = PolicyLoader.load(
                from: StaticPolicySource(
                    managed: ["policy.deployment.mode": raw], user: ["policy.deployment.mode": "ordinary"]))
            #expect(!policy.network.isValid)
            #expect(policy.network.mode == .airGapped)
        }
    }

    @Test func managedEnvelopePreventsUserGrants() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: ["policy.deployment.mode": "internalOnly"],
                user: ["policy.network": ["localIPC": true, "services": ["icons.assets": ["enabled": true]]]]))
        #expect(policy.network.services.isEmpty)
        #expect(!policy.network.localIPC)
        let managedNetwork = PolicyLoader.load(
            from: StaticPolicySource(
                managed: ["policy.network": ["localIPC": false]], user: ["policy.deployment.mode": "ordinary"]))
        #expect(!managedNetwork.network.localIPC)
    }

    @Test func invalidAndPartialInputDeniesWholeSnapshot() {
        let invalid: [Any] = [
            "allow", ["unknown": true], ["services": "all"], ["localIPC": 1],
            ["services": ["unknown.service": ["enabled": false]]],
            ["services": ["icons.assets": ["enabled": true, "origins": ["https://ok.example", "*"]]]],
            ["services": ["icons.assets": ["origins": ["https://ok.example"]]]],
            ["services": ["icons.assets": ["enabled": "true"]]],
            ["services": ["icons.assets": ["enabled": true, "endpoint": "https://mirror.example/index"]]],
            ["services": ["icons.assets": ["enabled": true, "typo": false]]],
        ]
        for value in invalid {
            let policy = PolicyLoader.load(
                from: StaticPolicySource(
                    managed: ["policy.network": value], user: ["policy.network": [:]]))
            #expect(!policy.network.isValid)
            #expect(policy.diagnostics.allSatisfy { !$0.description.contains("https:") })
        }
        let typo = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.network.enable": true]))
        #expect(!typo.network.isValid)
        let sensitiveKey = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.network.https://private.example/?token=secret": true
            ]))
        #expect(sensitiveKey.diagnostics.allSatisfy { !$0.description.contains("secret") })
    }

    /// Profiles can't be installed in tests, so simulated keys stand in for forced ones: both reach the
    /// loader through the macOS source's key list, while unforced user keys never poison the snapshot.
    @Test func macSourceReportsMisspelledManagedDeploymentKey() throws {
        let suite = "NetworkPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("airGapped", forKey: "policy.deployment.mdoe")
        let user = PolicyLoader.load(from: UserDefaultsPolicySource(defaults: defaults))
        #expect(user.network.isValid && user.network.mode == .ordinary)
        let managed = PolicyLoader.load(
            from: UserDefaultsPolicySource(defaults: defaults, simulatedManagedKeys: ["policy.deployment.mdoe"]))
        #expect(!managed.network.isValid)
        #expect(managed.diagnostics.allSatisfy { !$0.description.contains("mdoe") })
    }

    @Test func configuredMirrorAndExplicitLocalPermission() throws {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.deployment.mode": "internalOnly",
                "policy.network": [
                    "localIPC": true,
                    "services": [
                        "icons.index": [
                            "enabled": true, "origins": ["https://MIRROR.example:443"],
                            "endpoint": "https://mirror.example/registry.json",
                        ]
                    ],
                ],
            ]))
        #expect(policy.network.isValid)
        #expect(policy.network.localIPC)
        #expect(policy.network.services[.iconIndex]?.endpoint?.path == "/registry.json")
        #expect(policy.network.services[.iconIndex]?.origins == [try #require(NetworkOrigin("https://mirror.example"))])
    }

    @Test func originsAreExactAndUnambiguous() throws {
        #expect(NetworkOrigin("https://EXAMPLE.com") == NetworkOrigin("https://example.com:443/"))
        #expect(NetworkOrigin("https://example.com:444") != NetworkOrigin("https://example.com"))
        #expect(NetworkOrigin("http://127.0.0.2:8080")?.isLoopback == true)
        #expect(NetworkOrigin("http://[0:0:0:0:0:0:0:1]:8080") == NetworkOrigin("http://[::1]:8080"))
        #expect(NetworkOrigin("http://[::ffff:127.0.0.1]:8080")?.isLoopback == false)
        #expect(NetworkOrigin("https://localhost")?.isLoopback == false)
        #expect(NetworkOrigin("https://127.0.0.1.example")?.isLoopback == false)
        for text in [
            "https://user:secret@example.com", "https://example.com?token=x", "https://example.com/#x",
            "https://example.com/path", "https://*.example.com", "https://example.com.", "http://127.1",
            "http://2130706433", "http://0177.0.0.1", "http://0x7f000001", "file:///tmp/file",
            "https://example.com:", "https://example.com:0", "https://example.com:65536", "http://[fe80::1%25en0]",
        ] { #expect(NetworkOrigin(text) == nil) }
    }

    @Test func mcpTransportsAreAlternativesAndARequiredServerNeedsItsOwn() {
        func load(off services: [String]) -> NativePolicy {
            PolicyLoader.load(
                from: StaticPolicySource(managed: [
                    "policy.mcp.required": [["name": "audit", "command": "auditd"]],
                    "policy.network": [
                        "services": Dictionary(uniqueKeysWithValues: services.map { ($0, ["enabled": false]) })
                    ],
                ]))
        }
        let sseOff = load(off: ["mcp.sse"])
        #expect(sseOff.decision(for: .mcpExecution) == .required)
        #expect(sseOff.decision(for: .agentExecution) == .allowed)

        let stdioOff = load(off: ["mcp.stdio"])
        #expect(stdioOff.decision(for: .mcpExecution) == .disabled(.serviceDisabled(.mcpStdio), conflict: true))
        #expect(stdioOff.decision(for: .agentExecution) == .disabled(.requiredButDenied(.mcpExecution)))

        let allOff = load(off: ["mcp.stdio", "mcp.http", "mcp.sse"])
        #expect(allOff.decision(for: .mcpExecution).state == .disabled)
    }
}
