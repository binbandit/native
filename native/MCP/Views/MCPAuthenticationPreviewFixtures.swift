import Foundation
import SwiftUI

extension View {
    /// Replaces the app content, including its startup tasks, with inert status fixtures.
    @ViewBuilder func mcpAuthenticationFixture() -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "nativeMCPAuthenticationFixture") {
            ScrollView { MCPAuthenticationPreview() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.dsSurface)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
import MCPClient

enum MCPAuthenticationPreviewFixtures {
    static func entry(_ authentication: MCPAuthenticationStatus) -> ConfiguredServer {
        let url = URL(string: "https://docs.example.com/mcp") ?? URL(filePath: "/fixture")
        var entry = ConfiguredServer(
            server: MCPServerConfig(name: "docs", transport: .http(url: url)),
            format: authentication == .unknown ? .claudeCode : .codex,
            scope: .user, source: URL(filePath: "/fixture/config.toml"))
        entry.authentication = authentication
        return entry
    }

    static func library(_ authentication: MCPAuthenticationStatus) -> MCPLibrary {
        let entry = entry(authentication)
        let library = MCPLibrary(
            secretStore: MemorySecretStore(), storeURL: nil,
            initialConfigurations: [
                entry.format: AgentMCPConfiguration(format: entry.format, servers: [entry])
            ])
        library.reports[.agent(entry.id)] = MCPProbeReport(
            status: .needsAuth(MCPAuthChallenge(statusCode: 401, sentCredentials: false)),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000), duration: .zero)
        return library
    }
}

struct MCPAuthenticationPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach([MCPAuthenticationStatus.signedIn, .signedOut, .unknown], id: \.self) { status in
                let library = MCPAuthenticationPreviewFixtures.library(status)
                let entry = MCPAuthenticationPreviewFixtures.entry(status)
                MCPAgentServerRow(
                    library: library,
                    group: MCPAgentServerGroup(endpoint: entry.server.endpoint, entries: [entry]), project: nil,
                    isExpanded: .constant(true), onCommand: { _ in })
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 760)
    }
}
#endif
