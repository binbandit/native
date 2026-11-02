import ACP
import Foundation
import MCP

extension TaskOrchestrator {
    /// Bounded observations only: discovery never starts an agent or probes authentication.
    public func listAgents(
        for caller: OrchestrationCaller, search: String? = nil, limit: Int = 20
    ) async throws -> MCPToolResult {
        guard await runtime.isReady else { throw MCPToolError("Native isn't ready yet. Try again shortly.") }
        let all = await runtime.taskAgents().filter {
            guard let search, !search.isEmpty else { return true }
            return $0.id.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search)
        }
        let agents = Array(all.prefix(min(max(limit, 1), 40)))
        let candidates: [JSON] = agents.map { agent in
            let settings: [JSON] = agent.configOptions.prefix(12).map { option in
                var entry: [String: JSON] = [
                    "id": .string(option.id), "category": .string(option.category ?? "unknown"),
                ]
                if case .select(let current, let choices) = option.kind {
                    entry["current"] = .string(current)
                    entry["values"] = .array(choices.prefix(40).map { .string($0.value) })
                    entry["omitted_values"] = .number(Double(max(0, choices.count - 40)))
                }
                return .object(entry)
            }
            return .object([
                "id": .string(agent.id), "name": .string(agent.name), "is_you": .bool(agent.id == caller.agent),
                "available": .bool(agent.unavailableReason == nil),
                "reason": agent.unavailableReason.map(JSON.string) ?? .null,
                "settings": .array(settings), "settings_known": .bool(!agent.configOptions.isEmpty),
                "omitted_settings": .number(Double(max(0, agent.configOptions.count - 12))),
            ])
        }
        var entries: [JSON] = []
        var bytes = 0
        for candidate in candidates {
            let size = try JSONEncoder().encode(candidate).count
            guard bytes + size <= 32_768 else { break }
            entries.append(candidate)
            bytes += size
        }
        let lines = agents.prefix(entries.count).map {
            "- \($0.id): \($0.name)" + ($0.id == caller.agent ? " (the agent you are)" : "")
                + ($0.unavailableReason.map { ": \($0)" } ?? "")
        }
        return MCPToolResult(
            text: "Agents you can start tasks on (pass the id as `agent`):\n" + lines.joined(separator: "\n")
                + "\nSettings are last observed, may be incomplete, and are validated on the new session before its first prompt. Unknown authentication is not proof of sign-in. Checkout accepts an existing absolute directory; worktree creation is not supported.",
            structuredContent: .object([
                "agents": .array(entries), "omitted_agents": .number(Double(all.count - entries.count)),
                "durable_creation_and_completion": .bool(await runtime.supportsDurableTasks),
                "default_checkout": .string(caller.cwd.path(percentEncoded: false)),
            ]))
    }
}
