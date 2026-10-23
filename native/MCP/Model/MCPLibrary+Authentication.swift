import Exec
import Foundation
import MCPClient
import os

extension MCPLibrary {
    /// Includes worktrees that aren't registered projects, using the same identity as task rows.
    func configuredServer(for key: MCPServerKey) -> ConfiguredServer? {
        guard case .agent(let id) = key else { return nil }
        return configurations.values.lazy.flatMap(\.servers).first { $0.id == id }
            ?? sessionEntries.values.lazy.flatMap { $0 }.compactMap {
                if case .agent(let entry) = $0 { entry } else { nil }
            }.first { $0.id == id }
    }

    /// `codex mcp list --json`: read-only, and the only way to see what Codex's plugins add.
    func codexListing(environment: [String: String]) async -> CodexListing? {
        do {
            let result = try await runner.run(
                Command("codex", ["mcp", "list", "--json"], environment: environment, timeout: .seconds(20)))
            guard result.succeeded else { return nil }
            return try CodexListing.decode(result.standardOutput)
        } catch {
            logger.info("No Codex MCP listing: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
