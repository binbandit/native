import Exec
import Foundation
import MCPClient

extension MCPLibrary {
    /// Runs an agent's own CLI to change its configuration (the only way Native changes it), then
    /// reads the configuration again so the change shows.
    @discardableResult
    func run(_ command: AgentCLICommand) async -> MCPCommandRun {
        runningCommand = command
        defer { runningCommand = nil }
        let environment = await host?.mcpEnvironment() ?? [:]
        let run: MCPCommandRun
        do {
            let result = try await runner.run(command.command(environment: environment))
            let output = [result.output, result.errorOutput].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "\n")
            run = MCPCommandRun(command: command, succeeded: result.succeeded, output: output)
        } catch {
            run = MCPCommandRun(command: command, succeeded: false, output: error.localizedDescription)
        }
        lastCommandRun = run
        await readConfigurations()
        return run
    }

    /// Copies an agent's server into Native's managed servers, so every agent gets it. The agent's
    /// own copy stays, and Native won't hand that agent a second one.
    @discardableResult
    func importServer(_ entry: ConfiguredServer) async -> ManagedServer? {
        let environment = await host?.mcpEnvironment() ?? [:]
        let projects: ManagedServer.Selection = entry.scope.project.map { .only([ProjectPath.key($0)]) } ?? .all
        guard
            case (var server, let secrets)? = ManagedServer.importing(
                entry, resolvedWith: environment, projects: projects)
        else {
            problem =
                "\(entry.name) uses the SSE transport, which Native can't hand to agents. Ask its maker for a Streamable HTTP URL."
            return nil
        }
        server.name = availableName(for: server.name)
        save(server, secrets: secrets)
        return server
    }

    /// `name`, or `name-2`, `name-3`… when a managed server already has it.
    func availableName(for name: String, excluding id: UUID? = nil) -> String {
        let taken = Set(servers.filter { $0.id != id }.map(\.name)).union(reservedNames())
        guard taken.contains(name) else { return name }
        return (2...).lazy.map { "\(name)-\($0)" }.first { !taken.contains($0) } ?? name
    }
}

/// How an agent CLI command went: its exit and what it printed.
struct MCPCommandRun: Hashable {
    let command: AgentCLICommand
    let succeeded: Bool
    let output: String
}
