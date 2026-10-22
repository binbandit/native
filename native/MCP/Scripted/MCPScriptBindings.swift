import ACP
import Foundation
import MCP
import MCPClient
import NativeOrchestration
import ScriptRuntime

/// Binds the servers set to run through scripts into `run_script` as `tools.<server>.<tool>`, so
/// their tools are a search away for every session without their schemas in its context. A call
/// that can make changes is approved like the agent's own (`MCPScriptRun`).
nonisolated final class MCPScriptBindings: OrchestrationScriptBindings {
    typealias Resolve =
        @Sendable @MainActor (URL) async -> (servers: [MCPScriptedServer], environment: [String: String])

    typealias StartRun = @Sendable @MainActor (UUID, ContinuousClock.Instant) -> MCPScriptRun?

    private let connections: MCPScriptConnections
    private let resolve: Resolve
    private let startRun: StartRun

    init(connections: MCPScriptConnections, resolve: @escaping Resolve, startRun: @escaping StartRun) {
        self.connections = connections
        self.resolve = resolve
        self.startRun = startRun
    }

    @MainActor convenience init(library: MCPLibrary) {
        self.init(
            connections: library.scriptConnections,
            resolve: { [weak library] directory in
                guard let library, let host = library.host else { return ([], [:]) }
                let environment = await host.mcpEnvironment()
                return (library.scriptedServers(in: directory, environment: environment), environment)
            },
            startRun: { [weak library] clientID, deadline in
                library.map { MCPScriptRun(clientID: clientID, deadline: deadline, library: $0) }
            })
    }

    func summary(for caller: OrchestrationCaller) async -> OrchestrationScriptSummary? {
        let servers = await resolve(caller.cwd).servers
        guard !servers.isEmpty else { return nil }
        let names = servers.map { "tools.\($0.name).* (the \($0.name) MCP server's tools)" }
        return OrchestrationScriptSummary(
            description: names.joined(separator: ", ")
                + ". A call to one that can make changes waits for the user's approval, unless this task runs tool calls without asking; a declined call rejects with the reason.",
            isReadOnly: servers.allSatisfy(\.toolsAreReadOnly))
    }

    func bindings(for caller: OrchestrationCaller, until deadline: ContinuousClock.Instant) async -> [ScriptBinding] {
        let (servers, environment) = await resolve(caller.cwd)
        guard !servers.isEmpty, let run = await startRun(caller.clientID, deadline) else { return [] }
        // Servers start at once rather than one after another: the first script waits for all.
        return await withTaskGroup(of: (Int, [ScriptBinding]).self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    switch await self.connections.session(for: server, environment: environment) {
                    case .success(let session):
                        let tools = session.tools.filter { !$0.info.name.isEmpty }
                        return (index, tools.map { self.binding($0, of: server, in: session, run: run) })
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

    private func binding(
        _ tool: MCPSession.Tool, of server: MCPScriptedServer, in session: MCPSession, run: MCPScriptRun
    ) -> ScriptBinding {
        let info = tool.info
        let connections = connections
        return ScriptBinding(
            path: [server.name, info.name],
            summary: info.description ?? info.title,
            inputSchema: tool.inputSchema.flatMap { try? ScriptJSON(encoding: $0) },
            outputSchema: tool.outputSchema.flatMap { try? ScriptJSON(encoding: $0) },
            siteHandler: { input, site in
                let id = await run.begin(info, of: server, input: input, site: site)
                if case .declined(let reason) = await run.approve(id, tool: info, of: server) {
                    await run.update(id, to: .failed)
                    throw ScriptToolError(reason)
                }
                await run.update(id, to: .inProgress)
                let arguments = try JSON(encoding: input)
                let result: JSON
                do throws(MCPSessionError) {
                    result = try await session.call(info.name, arguments: arguments)
                } catch {
                    await run.update(id, to: .failed)
                    // A server that went away is started again by the next script.
                    await connections.forget(server.key)
                    throw ScriptToolError("\(server.name) didn't answer: \(error.message)")
                }
                let failed = result["isError"] == .bool(true)
                await run.update(id, to: failed ? .failed : .completed)
                if failed { throw ScriptToolError(Self.text(of: result)) }
                if let structured = result["structuredContent"] { return try ScriptJSON(encoding: structured) }
                return .string(Self.text(of: result))
            })
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
