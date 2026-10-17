import ACP
import Foundation

extension ContextReport {
    /// Whether the report lists any of the user's own setup: MCP tools, memory files, skills, agents.
    var hasContributors: Bool {
        !(mcpTools.isEmpty && memoryFiles.isEmpty && skills.isEmpty && agents.isEmpty)
    }

    /// The agent's own total for a kind of contributor ("MCP tools", "Memory files"), which is
    /// exact where adding up the rounded per-item counts drifts.
    func categoryTokens(_ name: String) -> Int? {
        categories.first { $0.kind == .used && $0.name.caseInsensitiveCompare(name) == .orderedSame }?.tokens
    }

    /// An MCP server's share of the "MCP tools" total, apportioned by its tools' counts, so servers
    /// add up to the category the table shows rather than to a sum of rounded figures.
    func tokens(of server: MCPServer) -> Int {
        let toolTotal = mcpTools.reduce(0) { $0 + $1.tokens }
        guard let category = categoryTokens("MCP tools"), toolTotal > 0 else { return server.tokens }
        return Int((Double(server.tokens) / Double(toolTotal) * Double(category)).rounded())
    }
}
