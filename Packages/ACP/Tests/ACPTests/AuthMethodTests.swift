import Foundation
import Testing

@testable import ACP

/// Sign-in methods and status, from the adapters Native runs. The `authMethods` were captured
/// 2026-10-20 by sending Native's `initialize` to codex-acp 2.2.2 and claude-agent-acp 0.93.0 in a
/// clean environment, verbatim.
struct AuthMethodTests {
    /// Native's own capabilities: an API key and the browser login.
    static let codex =
        #"[{"_meta":{"api-key":{"provider":"openai"}},"description":"Use an API key to authenticate","id":"api-key","name":"API Key"},{"description":"Use ChatGPT to authenticate","id":"chat-gpt","name":"ChatGPT"}]"#
    /// Advertising URL elicitations adds the device code.
    static let codexWithLinks =
        #"[{"_meta":{"api-key":{"provider":"openai"}},"description":"Use an API key to authenticate","id":"api-key","name":"API Key"},{"description":"Use ChatGPT to authenticate","id":"chat-gpt","name":"ChatGPT"},{"description":"Sign in to ChatGPT by opening a verification page and entering a one-time code","id":"chat-gpt-device-code","name":"ChatGPT (device code)"}]"#
    /// Advertising `auth.terminal`; with Native's capabilities Claude Code lists none.
    static let claudeWithTerminal =
        #"[{"args":["--cli","auth","login","--claudeai"],"description":"Use Claude subscription ","id":"claude-ai-login","name":"Claude Subscription","type":"terminal"},{"args":["--cli","auth","login","--console"],"description":"Use Anthropic Console (API usage billing)","id":"console-login","name":"Anthropic Console","type":"terminal"}]"#
    /// The same with `NO_BROWSER` set: the terminal login that works without one.
    static let claudeWithoutBrowser =
        #"[{"args":["--cli"],"description":"Run `claude /login` in the terminal","id":"claude-login","name":"Log in with Claude","type":"terminal"}]"#

    static func methods(_ json: String) throws -> [AuthMethod] {
        try JSONDecoder().decode([AuthMethod].self, from: Data(json.utf8))
    }

    @Test func codexTakesAnAPIKeyInAuthenticate() throws {
        let methods = try Self.methods(Self.codex)

        #expect(methods.map(\.kind) == [.apiKey(provider: "openai"), .agent])
        #expect(methods.map(\.takesSecret) == [true, false])
        #expect(try Self.methods(Self.codexWithLinks).map(\.id) == ["api-key", "chat-gpt", "chat-gpt-device-code"])
    }

    @Test func claudeCodeOffersTerminalLogins() throws {
        #expect(
            try Self.methods(Self.claudeWithTerminal).map(\.terminal) == [
                .agent(arguments: ["--cli", "auth", "login", "--claudeai"]),
                .agent(arguments: ["--cli", "auth", "login", "--console"]),
            ])
        #expect(try Self.methods(Self.claudeWithoutBrowser).map(\.terminal) == [.agent(arguments: ["--cli"])])
    }

    /// ACP's `env_var` method, from its first draft (`varName`) and its last (`vars`, with `link`).
    @Test func environmentMethodsNameTheirVariables() throws {
        let first = try Self.methods(
            #"[{"id":"openai","name":"OpenAI API key","type":"env_var","varName":"OPENAI_API_KEY"}]"#)[0]
        let last = try Self.methods(
            #"[{"id":"azure","name":"Azure OpenAI","type":"env_var","link":"https://example.com/keys","vars":[{"name":"AZURE_OPENAI_API_KEY","label":"API key"},{"name":"AZURE_OPENAI_ENDPOINT","label":"Endpoint","secret":false},{"name":"AZURE_ORG","optional":true}]}]"#
        )[0]

        #expect(first.kind == .environment([AuthMethod.Variable(name: "OPENAI_API_KEY")]))
        #expect(first.secretVariable?.name == "OPENAI_API_KEY")
        #expect(last.credentialsPage == URL(string: "https://example.com/keys"))
        #expect(
            last.kind
                == .environment([
                    AuthMethod.Variable(name: "AZURE_OPENAI_API_KEY", label: "API key"),
                    AuthMethod.Variable(name: "AZURE_OPENAI_ENDPOINT", label: "Endpoint", isSecret: false),
                    AuthMethod.Variable(name: "AZURE_ORG", isOptional: true),
                ]))
        // Two required values: not something one key field can fill in.
        #expect(!last.takesSecret)
    }

    @Test func unknownKindsArePreservedVerbatim() throws {
        let json = #"{"id":"sso","name":"Company SSO","type":"oauth_device","issuer":"https://example.com"}"#
        let method = try JSONDecoder().decode(AuthMethod.self, from: Data(json.utf8))
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(method))

        #expect(method.kind == .unknown(type: "oauth_device"))
        #expect(encoded == (try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
    }

    @Test(arguments: [
        AuthMethod(id: "agent", name: "Agent"),
        AuthMethod(id: "key", name: "Key", kind: .apiKey(provider: "openai")),
        AuthMethod(
            id: "env", name: "Env", description: "A key",
            kind: .environment([AuthMethod.Variable(name: "ANTHROPIC_API_KEY", label: "API key")]),
            credentialsPage: URL(string: "https://example.com")),
        AuthMethod(id: "link", name: "Link", kind: .link),
        AuthMethod(id: "terminal", name: "Terminal", terminal: .agent(arguments: ["login"])),
        AuthMethod(id: "command", name: "Command", terminal: .command("/bin/login-tool", arguments: ["-x"])),
        AuthMethod(id: "future", name: "Future", kind: .unknown(type: "_vendor/thing")),
    ])
    func methodsMadeInCodeRoundTrip(_ method: AuthMethod) throws {
        let decoded = try JSONDecoder().decode(AuthMethod.self, from: JSONEncoder().encode(method))

        #expect(decoded == method)
    }

    @Test func pluginsDeclareLinkMethodsWithNativesType() throws {
        let method = try Self.methods(
            #"[{"id":"chat-gpt-device-code","name":"ChatGPT (device code)","type":"_native/link"}]"#)[0]

        #expect(method.kind == .link)
        #expect(!method.takesSecret)
    }

    @Test func authenticateSendsTheKeyInMetaAndNeverPrintsIt() throws {
        let key = "test-key-0000"
        let request = AuthenticateRequest(methodId: "api-key", apiKey: key)
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))

        #expect(json["_meta"]?["api-key"]?["apiKey"] == .string(key))
        for printed in [
            String(describing: request), String(reflecting: request),
            "\(Mirror(reflecting: request).children.map(\.value))",
        ] {
            #expect(!printed.contains(key))
        }
        let plain = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(AuthenticateRequest(methodId: "chat-gpt")))
        #expect(plain == .object(["methodId": .string("chat-gpt")]))
    }

    /// The payload shapes both adapters' sources send (`AuthStatusMeta`, `auth-status.js`).
    @Test func authStatusReportsWhoIsSignedIn() throws {
        func status(_ json: String) throws -> AgentAuthStatus {
            try JSONDecoder().decode(AuthStatusNotification.self, from: Data(json.utf8)).authStatus
        }

        let signedOut = try status(#"{"authStatus":{"kind":"none","label":"Not logged in"}}"#)
        let account = try status(
            #"{"authStatus":{"kind":"account","label":"ChatGPT Pro","account":{"email":"someone@example.com","plan":"pro"}}}"#
        )
        let key = try status(
            #"{"authStatus":{"kind":"api_key","label":"Anthropic API key","detail":"ANTHROPIC_API_KEY"}}"#)
        let future = try status(#"{"authStatus":{"kind":"passkey","label":"Passkey"}}"#)

        #expect(!signedOut.isSignedIn && signedOut.kind == .signedOut)
        #expect(account == AgentAuthStatus(kind: .account, label: "ChatGPT Pro", email: "someone@example.com"))
        #expect(key.kind == .apiKey && key.detail == "ANTHROPIC_API_KEY")
        #expect(future.kind == .unknown("passkey") && future.isSignedIn)
        #expect(try JSONDecoder().decode(AgentAuthStatus.self, from: JSONEncoder().encode(account)) == account)
    }

    @Test func capabilitiesSayWhetherTheAgentReportsAndSignsOut() throws {
        let claude = try JSONDecoder().decode(JSONValue.self, from: Data(Wire.initializeResult.utf8))

        #expect(
            AgentAuthCapabilities(initializeResult: claude) == AgentAuthCapabilities(logout: true, reportsStatus: true))
        #expect(
            AgentAuthCapabilities(initializeResult: .object(["agentCapabilities": .object([:])]))
                == AgentAuthCapabilities())
    }
}
