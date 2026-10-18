import Foundation
import Testing

@testable import NativePolicy

@Suite struct NativePolicyTests {
    private func load(managed: [PolicyKey: Any] = [:], user: [PolicyKey: Any] = [:]) -> NativePolicy {
        PolicyLoader.load(from: StaticPolicySource(
            managed: Dictionary(uniqueKeysWithValues: managed.map { ($0.key.rawValue, $0.value) }),
            user: Dictionary(uniqueKeysWithValues: user.map { ($0.key.rawValue, $0.value) })))
    }

    @Test func defaultsAllowEverything() {
        let policy = load()
        #expect(policy == .default)
        #expect(policy.agents.allows("codex"))
        #expect(policy.mcp.allows(name: "github"))
        #expect(policy.allowsPlugin("anything"))
        #expect(policy.scriptsEnabled && policy.labsEnabled && policy.updates.isEnabled)
        #expect(policy.telemetry.native == .user)
        #expect(policy.managedKeys.isEmpty && policy.diagnostics.isEmpty)
    }

    @Test func agents() {
        let policy = load(managed: [
            .agentsAllowed: ["claude-code"],
            .agentsEnvironment: ["claude-code": ["CLAUDE_CODE_USE_BEDROCK": "1"]],
        ])
        #expect(policy.agents.allows("claude-code"))
        #expect(!policy.agents.allows("codex"))
        #expect(policy.agents.environment["claude-code"] == ["CLAUDE_CODE_USE_BEDROCK": "1"])
        #expect(policy.isManaged(.agentsAllowed) && policy.isManaged(.agentsEnvironment))
    }

    @Test func mcpServers() {
        let policy = load(managed: [
            .mcpBlocked: ["github", "command:npx *@evil/*"],
            .mcpRequired: [
                ["name": "docs", "url": "https://mcp.example.com/docs", "headers": ["Authorization": "Bearer x"]],
                ["name": "lint", "command": "lintd", "args": ["--stdio"]],
            ],
        ])
        #expect(!policy.mcp.allows(name: "GitHub"))
        #expect(!policy.mcp.allows(name: "helper", command: "npx -y @evil/server"))
        #expect(policy.mcp.allows(name: "helper", command: "npx -y @good/server"))
        #expect(policy.mcp.blocked.compactMap(\.exactName) == ["github"])
        #expect(policy.mcp.required.map(\.name) == ["docs", "lint"])
        #expect(policy.mcp.required[1].transport == .stdio(command: "lintd", arguments: ["--stdio"], environment: [:]))
    }

    @Test func mcpAllowlistWithWildcards() {
        let policy = load(managed: [.mcpAllowed: ["internal-*"], .mcpBlocked: ["internal-legacy"]])
        #expect(policy.mcp.allows(name: "internal-search"))
        #expect(!policy.mcp.allows(name: "internal-legacy"))
        #expect(!policy.mcp.allows(name: "github"))
    }

    @Test func pluginsSkillsAndModes() {
        let policy = load(managed: [
            .pluginsAllowed: ["acme-tools"],
            .skillsBlocked: ["deploy"],
            .forbiddenPermissionModes: ["bypassPermissions"],
        ])
        #expect(policy.allowsPlugin("acme-tools") && !policy.allowsPlugin("other"))
        #expect(policy.blockedSkills == ["deploy"])
        #expect(policy.forbids(permissionMode: "bypassPermissions") && !policy.forbids(permissionMode: "default"))
    }

    @Test func switches() {
        let policy = load(managed: [
            .scriptsEnabled: false, .labsEnabled: false, .companionEnabled: false, .remoteHostsEnabled: false,
        ])
        #expect(!policy.scriptsEnabled && !policy.labsEnabled && !policy.companionEnabled && !policy.remoteHostsEnabled)
    }

    @Test func updatesAndSearch() {
        let policy = load(managed: [
            .updatesEnabled: false,
            .updatesFeedURL: "https://updates.example.com/appcast.xml",
            .updatesChannels: ["stable", "Beta"],
            .searchRetentionDays: 30,
        ])
        #expect(!policy.updates.isEnabled)
        #expect(policy.updates.feedURL == URL(string: "https://updates.example.com/appcast.xml"))
        #expect(policy.updates.allows(channel: "beta") && !policy.updates.allows(channel: "nightly"))
        #expect(policy.searchRetentionDays == 30)
    }

    @Test func telemetry() {
        let policy = load(managed: [
            .telemetryNative: "off",
            .telemetryEndpoints: [["url": "https://otel.example.com", "headers": ["x-key": "k"], "attributes": ["team": "web"]]],
        ])
        #expect(policy.telemetry.native == .off)
        #expect(policy.telemetry.endpoints == [TelemetryEndpoint(
            url: URL(string: "https://otel.example.com")!, headers: ["x-key": "k"], attributes: ["team": "web"])])
    }

    @Test func badValuesAreReportedAndIgnored() {
        let policy = load(managed: [
            .scriptsEnabled: "no",
            .updatesFeedURL: "file:///etc/passwd",
            .searchRetentionDays: 0,
            .telemetryNative: "sometimes",
            .updatesChannels: ["stable", "canary"],
            .mcpRequired: [["name": "both", "command": "x", "url": "https://x.example.com"]],
        ])
        #expect(policy.scriptsEnabled)
        #expect(policy.updates.feedURL == nil)
        #expect(policy.searchRetentionDays == nil)
        #expect(policy.telemetry.native == .user)
        #expect(policy.updates.allowedChannels == ["stable"])
        #expect(policy.mcp.required.isEmpty)
        let keys = Set(policy.diagnostics.map(\.key))
        #expect(keys == [
            PolicyKey.scriptsEnabled, .updatesFeedURL, .searchRetentionDays, .telemetryNative, .updatesChannels, .mcpRequired,
        ].map(\.rawValue).reduce(into: Set()) { $0.insert($1) })
        #expect(!policy.isManaged(.scriptsEnabled))
        #expect(policy.isManaged(.updatesChannels))
    }

    @Test func numbersAreNotBooleans() {
        let policy = load(managed: [.labsEnabled: NSNumber(value: 0), .searchRetentionDays: true])
        // A plist integer isn't a Boolean, and a Boolean isn't a number of days.
        #expect(policy.diagnostics.map(\.key).contains(PolicyKey.searchRetentionDays.rawValue))
        #expect(policy.searchRetentionDays == nil)
    }

    @Test func organizationThenUserThenDefault() {
        let both = load(managed: [.labsEnabled: false], user: [.labsEnabled: true])
        #expect(!both.labsEnabled && both.isManaged(.labsEnabled))

        let userOnly = load(user: [.labsEnabled: false])
        #expect(!userOnly.labsEnabled && !userOnly.isManaged(.labsEnabled))

        // A bad organization value falls back to the user's, and is reported.
        let badManaged = load(managed: [.labsEnabled: "maybe"], user: [.labsEnabled: false])
        #expect(!badManaged.labsEnabled && !badManaged.isManaged(.labsEnabled))
        #expect(badManaged.diagnostics.first?.origin == .organization)

        #expect(load().labsEnabled)
    }

    @Test func unknownManagedKeysAreReported() {
        let policy = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.agent.allowed": ["x"]]))
        #expect(policy.diagnostics.map(\.key) == ["policy.agent.allowed"])
    }

    @Test func userDefaultsSourceTreatsSimulatedKeysAsManaged() throws {
        let suite = "NativePolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: PolicyKey.scriptsEnabled.rawValue)
        defaults.set(false, forKey: PolicyKey.labsEnabled.rawValue)
        let source = UserDefaultsPolicySource(defaults: defaults, simulatedManagedKeys: [PolicyKey.scriptsEnabled.rawValue])
        let policy = PolicyLoader.load(from: source)
        #expect(policy.isManaged(.scriptsEnabled) && !policy.scriptsEnabled)
        #expect(!policy.isManaged(.labsEnabled) && !policy.labsEnabled)
    }

    @Test func updatesStreamPublishesChanges() async throws {
        let suite = "NativePolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        var updates = PolicyLoader.updates(from: UserDefaultsPolicySource(defaults: defaults), notificationCenter: center)
            .makeAsyncIterator()
        #expect(await updates.next()?.scriptsEnabled == true)
        defaults.set(false, forKey: PolicyKey.scriptsEnabled.rawValue)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        #expect(await updates.next()?.scriptsEnabled == false)
    }

    @Test func wildcards() {
        #expect(Wildcard.matches("npx *@evil/*", "npx -y @evil/x", caseSensitive: true))
        #expect(Wildcard.matches("a?c", "abc", caseSensitive: true))
        #expect(!Wildcard.matches("a?c", "abbc", caseSensitive: true))
        #expect(Wildcard.matches("*", "", caseSensitive: true))
    }
}
