import Foundation
import MCPClient

/// A server set to run through Native's scripts in some folder, ready to connect to.
nonisolated struct MCPScriptedServer: Hashable, Sendable {
    /// Its switch key (`MCPEndpointIdentity.key`): one connection however many agents name it.
    var key: String
    /// The name scripts reach it by: `tools.<name>.<tool>`.
    var name: String
    var config: MCPServerConfig
    /// Where a local server starts.
    var directory: String?
}

extension MCPLibrary {
    /// The servers `directory`'s sessions reach through scripts: Native's own and the agents', once
    /// each, resolved with their secrets and the user's environment.
    func scriptedServers(in directory: URL, environment: [String: String]) -> [MCPScriptedServer] {
        let folder = ProjectPath.key(directory)
        var found: [String: MCPScriptedServer] = [:]
        for server in servers where server.includes(directory: directory) {
            let key = server.transport.endpoint.key
            guard mode(of: key, in: directory) == .scripted, found[key] == nil else { continue }
            found[key] = MCPScriptedServer(
                key: key, name: server.name, config: server.config(with: secrets(for: server.id)), directory: folder)
        }
        for agent in agents {
            for entry in agentServers(agent.format, in: directory) where entry.status.isLoaded {
                let key = entry.server.endpoint.key
                guard mode(of: key, in: directory) == .scripted, found[key] == nil else { continue }
                found[key] = MCPScriptedServer(
                    key: key, name: entry.name,
                    config: entry.resolved(environment: environment, project: entry.scope.project ?? directory),
                    directory: folder)
            }
        }
        // Script paths need distinct names; a second server with a taken one gets a number.
        var taken: Set<String> = []
        return found.values.sorted { $0.name < $1.name }.map { server in
            var server = server
            var name = server.name
            var number = 2
            while taken.contains(name) {
                name = "\(server.name)_\(number)"
                number += 1
            }
            taken.insert(name)
            server.name = name
            return server
        }
    }

    /// Whether any server runs through scripts anywhere, so connections can close once none does.
    var scriptedKeys: Set<String> {
        Set(
            ([switches.global] + Array(switches.projects.values)).flatMap { modes in
                modes.filter { $0.value == .scripted }.keys
            })
    }
}
