import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

extension HostTasks {
    /// Called before the agent starts. Claude loads a Native-owned local plugin; Codex discovers a
    /// non-overwriting installation in its configured home. Development never writes user skills.
    func prepareSkill(for spec: AgentSpec, environment: [String: String]) -> [String: String] {
        skillInstallations[spec.id] = nil
        guard core.allows(.agentTools), let format = spec.nativeSkill,
            let cli = core.configuration.actionExecutable, !spec.id.isEmpty,
            spec.id.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains(
                    $0)
            })
        else { return environment }
        let environment = environment.merging(spec.env) { $1 }
        let root = core.configuration.location.directory.appending(path: "AgentSkills/" + spec.id)
        let destination: URL
        switch format {
        case .unknown:
            return environment
        case .claudeCode:
            destination = root.appending(path: "skills/native-app")
        case .codex:
            let home =
                environment["CODEX_HOME"].map { URL(filePath: $0) }
                ?? URL(filePath: environment["HOME"] ?? NSHomeDirectory()).appending(path: ".codex")
            // Isolated builds may only install under their own host directory.
            if core.configuration.location.isDevelopment,
                !home.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(
                    core.configuration.location.directory.resolvingSymlinksInPath().standardizedFileURL.path + "/")
            {
                return environment
            }
            destination = home.appending(path: "skills/native-app")
        }
        do {
            try NativeAgentSkill.install(at: destination, cli: cli.path)
            if format == .claudeCode {
                let manifest = root.appending(path: ".claude-plugin/plugin.json")
                try FileManager.default.createDirectory(
                    at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(#"{"name":"native-app","description":"Native task actions","version":"1.0.0"}"#.utf8).write(
                    to: manifest)
            }
            let sessions = root.appending(path: "sessions")
            try FileManager.default.createDirectory(
                at: sessions, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            skillInstallations[spec.id] = destination
            var result = environment
            result[NativeActionCLI.sessionsVariable] = sessions.path
            return result
        } catch {
            // No agent failure for an unavailable skill, and no user files overwritten: MCP remains.
            core.logger.error("Native's skill could not be installed for \(spec.id); using MCP.")
            return environment
        }
    }

    func usesMCP(agent: String) -> Bool {
        core.agents[agent]?.spec.nativeMCPEnabled ?? (skillInstallations[agent] == nil)
    }

    /// Per-session SDK options keep the endpoint out of model context and bind shell calls to the
    /// same signed identity as MCP. Merge with the policy translator's settings, never replace it.
    func agentMeta(
        for id: HostSessionID, agent: String, base: JSONValue?, servers: [JSONValue] = []
    ) async -> JSONValue? {
        guard core.agents[agent]?.spec.nativeSkill == .claudeCode,
            let skill = skillInstallations[agent], let url = await toolURL(for: id, base: servers)
        else { return base }
        var plugins: [JSONValue] = []
        if case .array(let existing) = base?["claudeCode"]?["options"]?["plugins"] { plugins = existing }
        let root = skill.deletingLastPathComponent().deletingLastPathComponent().path
        if !plugins.contains(where: { $0["path"]?.stringValue == root }) {
            plugins.append(.object(["type": .string("local"), "path": .string(root)]))
        }
        let overlay: JSONValue = .object([
            "claudeCode": .object([
                "options": .object([
                    "plugins": .array(plugins),
                    "env": .object([NativeActionCLI.endpointVariable: .string(url.absoluteString)]),
                ])
            ])
        ])
        return (base ?? .object([:])).merging(overlay)
    }

    /// Codex's shell exports CODEX_THREAD_ID. The file contains a signed credential, not merely the
    /// public thread id; the endpoint still resolves and authorizes the live session on every call.
    func writeSkillCredential(for session: HostSession) async {
        guard core.agents[session.record.agentID]?.spec.nativeSkill == .codex,
            skillInstallations[session.record.agentID] != nil,
            let thread = session.record.agentSessionID?.rawValue, UUID(uuidString: thread) != nil,
            let url = await toolURL(for: session.id, base: session.mcpServers)
        else { return }
        let root = core.configuration.location.directory.appending(
            path: "AgentSkills/" + session.record.agentID + "/sessions")
        let file = root.appending(path: thread.lowercased() + ".json")
        do {
            try JSONEncoder().encode(NativeActionCLI.Credential(endpoint: url.absoluteString)).write(
                to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            core.logger.error("Couldn't prepare a Native CLI session credential.")
        }
    }
}
