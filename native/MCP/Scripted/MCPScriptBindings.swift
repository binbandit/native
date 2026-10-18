import Foundation
import MCP
import MCPClient
import ScriptRuntime

/// Binds the servers set to run through scripts into `run_script` as `tools.<server>.<tool>`, so
/// their tools are a search away for every session without their schemas in its context. Only
/// read-only tools are bound: a script's calls skip the approval an agent's own calls get.
nonisolated final class MCPScriptBindings: OrchestrationScriptBindings {
    typealias Resolve = @Sendable @MainActor (URL) async -> (servers: [MCPScriptedServer], environment: [String: String])

    private let connections: MCPScriptConnections
    private let resolve: Resolve

    init(connections: MCPScriptConnections, resolve: @escaping Resolve) {
        self.connections = connections
        self.resolve = resolve
    }

    @MainActor convenience init(library: MCPLibrary) {
        self.init(connections: library.scriptConnections) { [weak library] directory in
            guard let library, let host = library.host else { return ([], [:]) }
            let environment = await host.mcpEnvironment()
            return (library.scriptedServers(in: directory, environment: environment), environment)
        }
    }

    func summary(for caller: OrchestrationCaller) async -> OrchestrationScriptSummary? {
        let servers = await resolve(caller.cwd).servers
        guard !servers.isEmpty else { return nil }
        let names = servers.map { "tools.\($0.name).* (the read-only tools of the \($0.name) MCP server)" }
        return OrchestrationScriptSummary(description: names.joined(separator: ", ") + ".", isReadOnly: true)
    }

    func bindings(for caller: OrchestrationCaller) async -> [ScriptBinding] {
        let (servers, environment) = await resolve(caller.cwd)
        // Servers start at once rather than one after another: the first script waits for all.
        return await withTaskGroup(of: (Int, [ScriptBinding]).self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    switch await self.connections.session(for: server, environment: environment) {
                    case .success(let session):
                        let tools = session.tools.filter { $0.info.isReadOnly == true && !$0.info.name.isEmpty }
                        return (index, tools.map { self.binding($0, of: server, in: session) })
                    case .failure(let error):
                        return (index, [Self.unavailable(server, error)])
                    }
                }
            }
            var bound: [(Int, [ScriptBinding])] = []
            for await result in group { bound.append(result) }
            return bound.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    private func binding(_ tool: MCPSession.Tool, of server: MCPScriptedServer, in session: MCPSession) -> ScriptBinding {
        let name = tool.info.name
        let connections = connections
        return ScriptBinding(
            path: [server.name, name],
            summary: tool.info.description ?? tool.info.title,
            inputSchema: tool.inputSchema.flatMap { try? ScriptJSON(encoding: $0) },
            outputSchema: tool.outputSchema.flatMap { try? ScriptJSON(encoding: $0) }
        ) { input in
            let arguments = try JSON(encoding: input)
            let result: JSON
            do throws(MCPSessionError) {
                result = try await session.call(name, arguments: arguments)
            } catch {
                // A server that went away is started again by the next script.
                await connections.forget(server.key)
                throw ScriptToolError("\(server.name) couldn't run \(name): \(error.message)")
            }
            if result["isError"] == .bool(true) { throw ScriptToolError(Self.text(of: result)) }
            if let structured = result["structuredContent"] { return try ScriptJSON(encoding: structured) }
            return .string(Self.text(of: result))
        }
    }

    /// Stands in for a server that couldn't be reached, so a script searching for it learns why.
    private static func unavailable(_ server: MCPScriptedServer, _ error: MCPSessionError) -> ScriptBinding {
        let message = "\(server.name) couldn't be reached: \(error.message)"
        return ScriptBinding(path: [server.name, "unavailable"], summary: message) { _ in
            throw ScriptToolError(message)
        }
    }

    /// A result's text content; other kinds are named, since a script can't use their bytes.
    private static func text(of result: JSON) -> String {
        guard case .array(let content)? = result["content"] else { return "" }
        return content.map { item in
            item["text"]?.stringValue ?? "[\(item["type"]?.stringValue ?? "content")]"
        }.joined(separator: "\n")
    }
}
