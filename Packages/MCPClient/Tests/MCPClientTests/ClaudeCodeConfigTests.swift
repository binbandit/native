import Foundation
import MCPClient
import Testing

@Suite("Claude Code configuration")
struct ClaudeCodeConfigTests {
    let files = FakeFiles([
        "/home/tester/.claude.json": "claude.json",
        "/home/tester/.claude/settings.json": "claude-settings.json",
        "/home/tester/.claude/plugins/installed_plugins.json": "claude-installed-plugins.json",
        "/home/tester/.claude/plugins/cache/example-marketplace/notes/1.0.0/.mcp.json": "claude-plugin.mcp.json",
        "/home/tester/.claude/plugins/cache/example-marketplace/linter/0.3.0/.mcp.json": "claude-plugin.mcp.json",
        "/work/app/.mcp.json": "project.mcp.json",
        "/work/site/.mcp.json": "project.mcp.json",
    ])

    private func read(environment: [String: String] = [:]) -> AgentMCPConfiguration {
        AgentConfigReader(files: files, home: .testHome, environment: environment, claudeManagedFile: URL(filePath: "/nowhere/managed-mcp.json"))
            .read(.claudeCode, projects: [.app, .site])
    }

    @Test func readsEveryScope() {
        let config = read()
        let byScope = Dictionary(grouping: config.servers) { $0.scope }
        #expect(byScope[.user]?.map(\.name) == ["docs", "inspector"])
        #expect(byScope[.local(.app)]?.map(\.name) == ["docs", "tracker"])
        #expect(byScope[.project(.app)]?.map(\.name) == ["design", "fresh", "legacy"])
        #expect(byScope[.plugin("notes")]?.map(\.name) == ["plugin:notes:notes"])
        #expect(config.accountConnectors == ["claude.ai Example Docs"])
        #expect(!config.isManagedOnly)
    }

    @Test func reportsServersItCantConnectTo() {
        let config = read()
        #expect(config.problems.map(\.message) == ["\"socket\": the ws transport isn't supported."])
    }

    @Test func projectServersNeedApproval() {
        let status = Dictionary(uniqueKeysWithValues: read().servers.filter { $0.scope == .project(.app) }.map { ($0.name, $0.status) })
        #expect(status == ["design": .enabled, "legacy": .disabled, "fresh": .awaitingApproval])
        // `enableAllProjectMcpServers` approves every one.
        let site = read().servers.filter { $0.scope == .project(.site) }
        #expect(site.allSatisfy { $0.status == .enabled })
    }

    @Test func pluginServersGetTheirRootFilledIn() throws {
        let notes = try #require(read().servers.first { $0.name == "plugin:notes:notes" })
        #expect(notes.server.transport == .stdio(command: "/home/tester/.claude/plugins/cache/example-marketplace/notes/1.0.0/bin/notes-server", arguments: ["--stdio"]))
        // The disabled plugin contributes nothing.
        #expect(!read().servers.contains { $0.name.contains("linter") })
    }

    @Test func localBeatsUserAndProjectDisablesApply() {
        let effective = read().effective(in: .app)
        let docs = effective.first { $0.name == "docs" }
        #expect(docs?.scope == .local(.app))
        #expect(docs?.server.transport.kind == .sse)
        #expect(effective.first { $0.name == "inspector" }?.status == .disabledInProject)
        #expect(effective.filter(\.status.isLoaded).map(\.name).sorted() == ["design", "docs", "plugin:notes:notes", "tracker"])
        // Elsewhere, only the user and plugin servers apply.
        #expect(read().effective(in: URL(filePath: "/elsewhere")).map(\.name).sorted() == ["docs", "inspector", "plugin:notes:notes"])
    }

    @Test func expandsVariablesLikeClaudeCode() throws {
        let inspector = try #require(read().servers.first { $0.name == "inspector" })
        let resolved = inspector.resolved(environment: ["HOME": "/Users/someone"], project: nil)
        guard case .stdio(_, _, let environment, _) = resolved.transport else { Issue.record("Expected stdio"); return }
        #expect(environment == ["INSPECTOR_HOME": "/Users/someone/Inspector", "INSPECTOR_MODE": "fast"])

        let tracker = try #require(read().servers.first { $0.name == "tracker" })
        #expect(tracker.resolved(environment: ["TRACKER_TOKEN": "abc"], project: .app).transport == .http(url: URL(string: "https://tracker.example.com/mcp")!, headers: ["Authorization": "Bearer abc"]))
        // Unknown variables stay as written, so the failure is visible.
        #expect(tracker.resolved(environment: [:], project: .app).transport.secretNames == ["Authorization"])
    }

    @Test func managedConfigurationReplacesEverything() {
        let managed = FakeFiles(["/home/tester/.claude.json": "claude.json", "/etc/managed-mcp.json": "project.mcp.json"])
        let config = AgentConfigReader(files: managed, home: .testHome, environment: [:], claudeManagedFile: URL(filePath: "/etc/managed-mcp.json")).read(.claudeCode, projects: [.app])
        #expect(config.isManagedOnly)
        #expect(config.effective(in: .app).allSatisfy { $0.scope == .managed })
    }

    @Test func followsClaudeConfigDirectory() {
        let moved = FakeFiles(["/custom/claude/.claude.json": "claude.json"])
        let config = AgentConfigReader(files: moved, home: .testHome, environment: ["CLAUDE_CONFIG_DIR": "/custom/claude"], claudeManagedFile: URL(filePath: "/none")).read(.claudeCode, projects: [])
        #expect(config.servers.map(\.name) == ["docs", "inspector"])
        #expect(config.files.first?.url.path(percentEncoded: false) == "/custom/claude/.claude.json")
    }

    @Test func missingFilesAreNotProblems() {
        let config = AgentConfigReader(files: FakeFiles([:]), home: .testHome, environment: [:], claudeManagedFile: URL(filePath: "/none")).read(.claudeCode, projects: [.app])
        #expect(config.servers.isEmpty)
        #expect(config.problems.isEmpty)
        #expect(config.files.map(\.exists) == [false, false])
    }
}
