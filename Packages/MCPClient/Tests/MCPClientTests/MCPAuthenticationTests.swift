import Foundation
import MCPClient
import Security
import Synchronization
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
        let signedOut = try CodexListing.decode(Fixture.data("codex-mcp-list.json"))
        var configuration = AgentMCPConfiguration(format: .codex).merging(signedIn)
        configuration = configuration.merging(signedOut)
        #expect(configuration.servers.first { $0.name == "docs" }?.authentication == .signedOut)
        configuration = configuration.merging(signedIn)
        #expect(configuration.servers.first { $0.name == "docs" }?.authentication == .signedIn)
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

    @Test func claudeReadsSharedKeychainAcrossTaskScopesAndRereadsChanges() throws {
        let keychain = FixtureCredentialKeychain(data: Fixture.data("claude-mcp-credentials.json"))
        let reader = ClaudeMCPAuthentication(files: FakeFiles([:]), keychain: keychain)
        let user = try claudeEntry()
        var project = user
        project.scope = .project(.app)
        let configuration = AgentMCPConfiguration(format: .claudeCode, servers: [user, project])
        func read() -> [MCPAuthenticationStatus] {
            reader.read(configuration, home: .testHome, environment: ["USER": "tester"], now: now)
                .servers.map(\.authentication)
        }
        // The access token is expired, but the owning agent can refresh the shared sign-in.
        #expect(read() == [.signedIn, .signedIn])
        keychain.set(Data("{\"mcpOAuth\":{}}".utf8))
        #expect(read() == [.signedOut, .signedOut])
        keychain.set(Fixture.data("claude-mcp-credentials.json"))
        #expect(read() == [.signedIn, .signedIn])
        #expect(keychain.lastQuery == "Claude Code-credentials|tester")
    }

    @Test func claudeFallbackAndKeychainPrecedence() throws {
        let files = FakeFiles(["/home/tester/.claude/.credentials.json": "claude-mcp-credentials.json"])
        let keychain = FixtureCredentialKeychain(data: nil)
        let reader = ClaudeMCPAuthentication(files: files, keychain: keychain)
        let configuration = AgentMCPConfiguration(format: .claudeCode, servers: [try claudeEntry()])
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: now).servers.first?.authentication
                == .signedIn)
        keychain.set(Data("{}".utf8))
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: now).servers.first?.authentication
                == .signedOut)
        keychain.set(Data("broken".utf8))
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: now).servers.first?.authentication
                == .unknown)
        keychain.fail()
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: now).servers.first?.authentication
                == .unknown)
    }

    @Test func claudeExpiredTokenWithoutRefreshRequiresSignIn() throws {
        let fixture = String(decoding: Fixture.data("claude-mcp-credentials.json"), as: UTF8.self)
            .replacingOccurrences(of: "\"refreshToken\": \"fixture-refresh\",", with: "")
        let keychain = FixtureCredentialKeychain(data: Data(fixture.utf8))
        let reader = ClaudeMCPAuthentication(files: FakeFiles([:]), keychain: keychain)
        let configuration = AgentMCPConfiguration(format: .claudeCode, servers: [try claudeEntry()])
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: now).servers.first?.authentication
                == .signedOut)
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: Date(timeIntervalSince1970: 1))
                .servers.first?.authentication == .signedIn)
    }

    @Test func claudeIdentityIncludesEndpointAndTransport() throws {
        let keychain = FixtureCredentialKeychain(data: Fixture.data("claude-mcp-credentials.json"))
        let reader = ClaudeMCPAuthentication(files: FakeFiles([:]), keychain: keychain)
        var other = try claudeEntry()
        other.server.transport = .sse(url: try #require(other.server.transport.url))
        let configuration = AgentMCPConfiguration(format: .claudeCode, servers: [other])
        #expect(
            reader.read(configuration, home: .testHome, environment: [:], now: now).servers.first?.authentication
                == .signedOut)
        other.server.transport = .http(url: try #require(URL(string: "https://other.example.com/mcp")))
        #expect(
            reader.read(
                AgentMCPConfiguration(format: .claudeCode, servers: [other]), home: .testHome, environment: [:],
                now: now
            )
            .servers.first?.authentication == .signedOut)
    }

    @Test func claudeUsesCustomCredentialDirectory() throws {
        let keychain = FixtureCredentialKeychain(data: nil)
        let files = FakeFiles(["/custom/.credentials.json": "claude-mcp-credentials.json"])
        let reader = ClaudeMCPAuthentication(files: files, keychain: keychain)
        let configuration = AgentMCPConfiguration(format: .claudeCode, servers: [try claudeEntry()])
        let result = reader.read(
            configuration, home: .testHome, environment: ["CLAUDE_CONFIG_DIR": "/custom", "USER": "tester"], now: now)
        #expect(result.servers.first?.authentication == .signedIn)
        #expect(keychain.lastQuery.hasPrefix("Claude Code-credentials-"))
    }

    private var challenge: MCPAuthChallenge { MCPAuthChallenge(statusCode: 401, sentCredentials: false) }
    private var anonymousChallenge: MCPProbeReport {
        MCPProbeReport(status: .needsAuth(challenge), startedAt: now, duration: .zero)
    }

    private func claudeEntry() throws -> ConfiguredServer {
        ConfiguredServer(
            server: MCPServerConfig(
                name: "docs", transport: .http(url: try #require(URL(string: "https://docs.example.com/mcp")))),
            format: .claudeCode, scope: .user, source: .testHome)
    }
}

private final class FixtureCredentialKeychain: MCPCredentialKeychain {
    private struct State { var data: Data?; var failed = false; var query = "" }
    private let state: Mutex<State>
    init(data: Data?) { state = Mutex(State(data: data)) }
    var lastQuery: String { state.withLock { $0.query } }
    func set(_ data: Data?) { state.withLock { $0.data = data } }
    func fail() { state.withLock { $0.failed = true } }
    func data(service: String, account: String) throws -> Data? {
        try state.withLock {
            $0.query = service + "|" + account
            if $0.failed { throw CocoaError(.fileReadNoPermission) }
            return $0.data
        }
    }
}
