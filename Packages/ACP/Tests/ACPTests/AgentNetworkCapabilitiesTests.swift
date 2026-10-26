import Foundation
import Testing

@testable import ACP

@Suite struct AgentNetworkCapabilitiesTests {
    static var route: AgentPrivateRoute {
        AgentPrivateRoute(
            identity: AgentRouteIdentity(
                routeID: "fixture", declarationID: "codex-responses-v1", cliVersion: "0.164.0", adapterVersion: "2.2.2"),
            origin: "http://127.0.0.1:8041", model: "fixture-model",
            authentication: .runtimeEnvironment("NATIVE_PROVIDER_KEY"))
    }

    @Test func candidateIsNotQualified() {
        #expect(!AgentNetworkCapabilities.codexCandidate.qualified)
        #expect(!Self.route.requiredControls.isSubset(of: AgentNetworkCapabilities.codexCandidate.controls))
    }

    @Test func routeCompositionPreservesMCPAndSkills() throws {
        let overrides = CodexConfigOverrides(disabledMCPServers: ["fixture"], disabledSkills: ["/fixture/skill"])
        let environment = try overrides.environment(for: Self.route)
        #expect(environment["MODEL_PROVIDER"] == "native_private")
        let encoded = try #require(environment["CODEX_CONFIG"])
        let config = try JSONDecoder().decode(JSONValue.self, from: Data(encoded.utf8))
        #expect(config["mcp_servers.fixture.enabled"] == .bool(false))
        #expect(config["skills"] == overrides.config["skills"])
        #expect(config["model"] == .string("fixture-model"))
        #expect(config["model_provider"] == .string("native_private"))
        #expect(config["model_providers"]?["native_private"]?["base_url"] == .string("http://127.0.0.1:8041/v1"))
        #expect(config["model_providers"]?["native_private"]?["requires_openai_auth"] == .bool(false))
        #expect(config["check_for_update_on_startup"] == .bool(false))
        #expect(!encoded.contains("api.openai.com"))
        #expect(!encoded.contains("chatgpt.com"))
    }

    @Test(arguments: [
        "https://user:secret@private.example", "https://private.example?key=secret", "https://private.example#secret",
        "http://private.example", "ftp://private.example", "https://private.example/v1", "https://private.example:0",
        "https://", "https://private.example:", "https://*.example", "https://127.1", "https://0177.0.0.1",
        "https://private.example.",
        "https://%70rivate.example", "https://private.example\\evil", "https://private.example:65536",
    ])
    func invalidOrigins(origin: String) {
        var route = Self.route
        route.origin = origin
        #expect(throws: AgentRouteFailure.self) { try CodexConfigOverrides().environment(for: route) }
    }

    @Test func missingCredentialReferenceAndUnknownVersionsFailLocally() {
        var route = Self.route
        route.authentication = .runtimeEnvironment("OPENAI_API_KEY")
        #expect(throws: AgentRouteFailure.unsupportedControl) { try CodexConfigOverrides().environment(for: route) }
        route = Self.route
        route.identity.cliVersion = "unknown"
        #expect(throws: AgentRouteFailure.unqualified) { try CodexConfigOverrides().environment(for: route) }
        route = Self.route
        route.identity.adapterVersion = "2.2.3"
        #expect(throws: AgentRouteFailure.unqualified) { try CodexConfigOverrides().environment(for: route) }
        route = Self.route
        route.authentication = .nativeCredential("fixture-reference")
        #expect(throws: AgentRouteFailure.unsupportedControl) { try CodexConfigOverrides().environment(for: route) }
    }

    @Test(arguments: ["CODEX_CONFIG", "CODEX_HOME", "OPENAI_BASE_URL", "HTTPS_PROXY", "NODE_EXTRA_CA_CERTS"])
    func conflictingInheritedConfiguration(variable: String) {
        #expect(throws: AgentRouteFailure.conflictingConfiguration) {
            try CodexConfigOverrides().environment(for: Self.route, inheriting: [variable: "fixture"])
        }
    }

    @Test func unsupportedControlsCannotBecomeEnvironmentHints() {
        for control in ["proxy", "bypass", "ca"] {
            var route = Self.route
            if control == "proxy" { route.proxyOrigin = "https://proxy.example" }
            if control == "bypass" { route.bypassProxy = true }
            if control == "ca" { route.customCAFile = "/fixture/root.pem" }
            #expect(throws: AgentRouteFailure.unsupportedControl) { try CodexConfigOverrides().environment(for: route) }
        }
    }

    @Test func errorsAreContentFreeAndUnknownControlsStayUnknown() throws {
        let control = try JSONDecoder().decode(
            AgentNetworkCapabilities.Control.self, from: Data("\"future-secret\"".utf8))
        #expect(control == .unknown)
        var route = Self.route
        route.origin = "https://canary-secret@private.example"
        do {
            _ = try CodexConfigOverrides().environment(for: route)
            Issue.record("Credential-bearing route accepted")
        } catch {
            #expect(error.localizedDescription == "Agent route denied (invalidRoute).")
        }
        let serialized = String(decoding: try JSONEncoder().encode(Self.route), as: UTF8.self)
        #expect(serialized.contains("NATIVE_PROVIDER_KEY"))
        #expect(!serialized.contains("canary-secret"))
    }
}
