import ACP
import Foundation
import MCP
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import NativePolicy
import Observation
import os

// Native's host and the tools. With `HostTasksSetting` on, the host serves them to its sessions
// and runs their tasks; the app mirrors those tasks and shows them as it always has. Otherwise the
// app serves them, and host sessions keep the URL they were first given: most launches give them
// nothing new, since the server's port and their tokens last. When they don't (sessions from before
// they lasted, or a move off a taken port), the app gives the host each session's current URL, so
// the next reload brings the tools back.
extension OrchestrationPlugin {
    /// Every time the host connects (a restart brings a new process), tells it who serves the tools,
    /// and follows its tasks when it does.
    func followHost(_ durableHost: DurableHost, model: AppModel) async {
        let epochs = Observations { () -> UUID? in
            if case .connected(let info)? = durableHost.connection { info.epoch } else { nil }
        }
        var configured: UUID?
        for await epoch in epochs {
            guard let epoch, epoch != configured, let client = durableHost.client else { continue }
            configured = epoch
            if HostTasksSetting.isEnabled, await serve(from: client, model: model) {
                continue
            }
            // The app serves them: an older host has no say, and this one leaves the app's entry alone.
            try? await client.configureTasks(ConfigureTasksParams(servesTools: false))
            await refreshURLs(in: durableHost, plugins: model.plugins)
        }
    }

    /// Has the host serve the tools, with the skills switched off here and the tools only the app
    /// answers, and mirrors its tasks. False when the host can't (it's older than the tools in the
    /// host).
    private func serve(from client: NativeHostClient, model: AppModel) async -> Bool {
        hostCalls.use(client)
        if HostTaskMirror.shared.answers(client) {
            await client.addAppToolHandler { [appOnlyTools] call in
                Task { await Self.answer(call, with: appOnlyTools, on: client) }
            }
        }
        do {
            try await client.configureTasks(
                ConfigureTasksParams(
                    servesTools: true, disabledSkills: Self.disabledSkills(in: model),
                    appTools: appOnlyTools.compactMap { Self.definition($0.declaration) }))
        } catch {
            Self.logger.error(
                "The host can't serve Native's tools, so the app does: \(error.localizedDescription, privacy: .public)")
            return false
        }
        handOverToHost()
        await HostTaskMirror.shared.follow(client, model: model)
        return true
    }

    /// Runs one of the app's own tools for a session the host serves, or says how it lists for it.
    nonisolated private static func answer(
        _ call: AppToolCall, with tools: [MCPTool<OrchestrationCaller>], on client: NativeHostClient
    ) async {
        let caller = OrchestrationCaller(
            clientID: call.sessionID.rawValue, agent: call.agentID,
            cwd: URL(filePath: call.cwd, directoryHint: .isDirectory))
        var answer = AppToolResult(callID: call.callID)
        if let tool = tools.first(where: { $0.name == call.tool }) {
            switch call.kind {
            case .listing:
                answer.listing = definition(await tool.definition(for: caller))
            case .call, .unknown:
                let arguments = (try? JSON(encoding: call.arguments)) ?? [:]
                let result = await tool(caller, arguments: arguments)
                answer.result = ToolResult(
                    text: result.text, structuredContent: result.structuredContent.flatMap(jsonValue),
                    isError: result.isError)
            }
        } else {
            answer.result = ToolResult(text: "This copy of Native has no tool named \(call.tool).", isError: true)
        }
        try? await client.answerAppTool(answer)
    }

    nonisolated private static func definition(_ json: JSON) -> AppToolDefinition? {
        (try? JSONEncoder().encode(json)).flatMap { try? JSONDecoder().decode(AppToolDefinition.self, from: $0) }
    }

    nonisolated private static func jsonValue(_ json: JSON) -> JSONValue? {
        (try? JSONEncoder().encode(json)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }

    /// Native's skills switched off, everywhere and per project, as the host applies them.
    private static func disabledSkills(in model: AppModel) -> [DisabledNativeSkill] {
        let ids = Set(NativeSkill.bundled().map(\.id))
        let folders = [nil] + model.projects.all.map { Optional($0.url) }
        return folders.map { folder in
            let context = SessionContext(
                clientID: UUID(), agent: model.agents.first?.agent.id ?? AgentDefinition.ID(rawValue: ""),
                agentName: "", sessionID: nil, cwd: folder ?? URL(filePath: "/"))
            let off = model.plugins.sessionPolicy(for: context).disabledSkills.compactMap(\.name).filter(ids.contains)
            return DisabledNativeSkill(folder: folder?.folderPath, skills: off.sorted())
        }
    }

    /// Once the server listens, hands every session the host runs this launch's URL for its next
    /// `session/load`. Sessions loaded right now keep the address they have; after a move, the
    /// status says so.
    func refreshURLs(in durableHost: DurableHost, plugins: PluginRegistry) async {
        let status = status
        let ready = Observations {
            guard case .connected = durableHost.connection else { return false }
            return status.launch != nil
        }
        for await isReady in ready where isReady {
            break
        }
        // Only for sessions that get the server at all: adding it to a stored list mustn't get past
        // the plugin's switch or the organization's policy.
        guard plugins.isEnabled(Self.id), PolicyCenter.shared.policy.mcp.allows(name: Self.serverName),
            let client = durableHost.client
        else { return }
        let sessions: [HostSessionSummary]
        do {
            sessions = try await client.sessions().filter { $0.origin != .announced }
        } catch {
            Self.logger.error("Couldn't list the host's sessions: \(error.localizedDescription, privacy: .public)")
            return
        }
        var refreshed = 0
        for session in sessions {
            guard let url = url(for: session.id.rawValue),
                let server = try? JSONDecoder().decode(
                    JSONValue.self, from: JSONEncoder().encode(MCPServer.http(name: Self.serverName, url: url)))
            else { continue }
            do {
                try await client.setMCPServers(
                    SetMCPServersParams(sessionID: session.id, mcpServers: [server], replacingNamed: true))
                refreshed += 1
            } catch {
                Self.logger.error(
                    "Couldn't update a host session's MCP URL: \(error.localizedDescription, privacy: .public)")
            }
        }
        if refreshed > 0 {
            status.leftSessionsBehind()
        }
    }
}
