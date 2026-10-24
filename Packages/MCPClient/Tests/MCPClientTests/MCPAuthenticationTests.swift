import Foundation
import MCPClient
import Testing

@Suite("MCP shared authentication")
struct MCPAuthenticationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func capturedCodexSignInSurvivesAnonymousProbe() throws {
        let listing = try CodexListing.decode(Fixture.data("codex-mcp-signed-in.json"))
        let configuration = AgentMCPConfiguration(format: .codex).merging(listing)
        let entry = try #require(configuration.servers.first)
        #expect(entry.authentication == .signedIn)
        #expect(MCPServerHealth(report: anonymousChallenge, authentication: entry.authentication) == .signedIn)
    }

    @Test func codexSignOutAndSignInReplacePreviousState() throws {
        let signedIn = try CodexListing.decode(Fixture.data("codex-mcp-signed-in.json"))
        let signedOutCapture = String(decoding: Fixture.data("codex-mcp-signed-in.json"), as: UTF8.self)
            .replacingOccurrences(of: "\"o_auth\"", with: "\"not_logged_in\"")
        let signedOut = try CodexListing.decode(Data(signedOutCapture.utf8))
        var configuration = AgentMCPConfiguration(format: .codex).merging(signedIn)
        configuration = configuration.merging(signedOut)
        #expect(configuration.servers.first { $0.name == "docs" }?.authentication == .signedOut)
        configuration = configuration.merging(signedIn)
        #expect(configuration.servers.first { $0.name == "docs" }?.authentication == .signedIn)
    }

    @Test(arguments: [nil, "", "fixture-token"] as [String?])
    func configuredBearerDoesNotProveSharedSignIn(token: String?) throws {
        let listing = try CodexListing.decode(Fixture.data("codex-mcp-missing-bearer.json"))
        let entry = try #require(AgentMCPConfiguration(format: .codex).merging(listing).servers.first)
        var environment: [String: String] = [:]
        environment["NATIVE_MCP_FIXTURE_TOKEN"] = token
        if token == nil {
            guard case .http(_, let headers) = entry.resolved(environment: environment, project: nil).transport else {
                Issue.record("Expected HTTP transport")
                return
            }
            #expect(headers["Authorization"] == nil)
        }
        // Even before a probe, a configured variable alone cannot establish a usable sign-in.
        #expect(entry.authentication == .unknown)
        #expect(MCPServerHealth(report: nil, authentication: entry.authentication) == .unchecked)
        #expect(
            MCPServerHealth(report: anonymousChallenge, authentication: entry.authentication) == .authenticationUnknown)
    }

    @Test func sameNameAtAnotherEndpointDoesNotBorrowSignIn() throws {
        let listing = try CodexListing.decode(Fixture.data("codex-mcp-signed-in.json"))
        let url = try #require(URL(string: "https://other.example.com/mcp"))
        let other = ConfiguredServer(
            server: MCPServerConfig(name: "docs", transport: .http(url: url)), format: .codex,
            scope: .project(.app), source: .app)
        let configuration = AgentMCPConfiguration(format: .codex, servers: [other]).merging(listing)
        #expect(configuration.servers.first?.authentication == .unknown)
        let full = AgentMCPConfiguration(format: .codex).merging(listing)
        #expect(configuration.withAuthentication(from: full).servers.first?.authentication == .unknown)
        var matching = other
        matching.server = try #require(full.servers.first).server
        #expect(
            AgentMCPConfiguration(format: .codex, servers: [matching]).withAuthentication(from: full)
                .servers.first?.authentication == .signedIn)
    }

    @Test func sameEndpointWithDifferentCredentialVariablesDoesNotBorrowSignIn() throws {
        let listing = try CodexListing.decode(Fixture.data("codex-mcp-signed-in.json"))
        let full = AgentMCPConfiguration(format: .codex).merging(listing)
        var other = try #require(full.servers.first)
        other.scope = .project(.app)
        for resolution in [
            ValueResolution.codex(passThrough: [], bearerTokenVariable: "PROJECT_TOKEN", headerVariables: [:]),
            .codex(passThrough: [], bearerTokenVariable: nil, headerVariables: ["X-Workspace": "PROJECT_WORKSPACE"]),
        ] {
            other.resolution = resolution
            let project = AgentMCPConfiguration(format: .codex, servers: [other])
            #expect(project.merging(listing).servers.first?.authentication == .unknown)
            other.authentication = .unknown
            #expect(
                AgentMCPConfiguration(format: .codex, servers: [other]).withAuthentication(from: full)
                    .servers.first?.authentication == .unknown)
        }
    }

    @Test func unknownOwnerDoesNotBecomeSignedOutFromAnAnonymous401() {
        #expect(MCPServerHealth(report: anonymousChallenge, authentication: .unknown) == .authenticationUnknown)
        #expect(MCPServerHealth(report: anonymousChallenge, authentication: .signedOut) == .needsAuth(challenge))
        #expect(MCPServerHealth(report: anonymousChallenge) == .needsAuth(challenge))
        #expect(MCPServerHealth(report: nil, authentication: .signedIn) == .signedIn)
        // No stored OAuth credential alone doesn't mean a public server needs authentication.
        #expect(MCPServerHealth(report: nil, authentication: .signedOut) == .unchecked)
    }

    @Test func rejectedConfiguredTokenAndConnectionFailureStillNeedAttention() {
        let rejected = MCPAuthChallenge(statusCode: 403, sentCredentials: true)
        let report = MCPProbeReport(status: .needsAuth(rejected), startedAt: now, duration: .zero)
        #expect(MCPServerHealth(report: report, authentication: .signedIn) == .needsAuth(rejected))
        let failure = MCPProbeFailure(stage: .connect, message: "Offline")
        let failed = MCPProbeReport(status: .failed(failure), startedAt: now, duration: .zero)
        #expect(MCPServerHealth(report: failed, authentication: .signedIn) == .failed(failure))
        #expect(
            MCPServerHealth(report: report, authentication: .signedIn, inactiveReason: "Off")
                == .inactive("Off"))
    }

    @Test func agentConfigurationLeavesSignInUnknown() throws {
        let files = FakeFiles([
            "/home/tester/.claude.json": "claude.json",
            "/home/tester/.cursor/mcp.json": "cursor-mcp.json",
        ])
        let reader = AgentConfigReader(files: files, home: .testHome, environment: [:])
        for format in [AgentConfigFormat.claudeCode, .cursor] {
            let configuration = reader.read(format, projects: [.app])
            #expect(!configuration.servers.isEmpty)
            for entry in configuration.servers {
                #expect(entry.authentication == .unknown)
                #expect(MCPServerHealth(report: nil, authentication: entry.authentication) == .unchecked)
                #expect(
                    MCPServerHealth(report: anonymousChallenge, authentication: entry.authentication)
                        == .authenticationUnknown)
            }
        }
    }

    private var challenge: MCPAuthChallenge { MCPAuthChallenge(statusCode: 401, sentCredentials: false) }
    private var anonymousChallenge: MCPProbeReport {
        MCPProbeReport(status: .needsAuth(challenge), startedAt: now, duration: .zero)
    }

}
