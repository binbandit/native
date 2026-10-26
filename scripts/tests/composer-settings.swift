import ACP
import Experiments
import Foundation
import NativeHostClient
import NativeHostProtocol
import SwiftUI

@testable import Native
@testable import NativeLink

private struct SettingsFailure: Error { let message: String }

/// An in-memory host transport records restarts without starting an agent or contacting a machine.
private actor SettingsHost: HostTransport {
    nonisolated let displayName = "Settings fixture"
    let hostID = HostID()
    private let epoch = UUID()
    private var peer: JSONRPCPeer?
    private(set) var restarts: [String] = []

    func connect() throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "settings-host"), label: "settings-host") {
            [weak self] event in
            if case .request(let message) = event { Task { await self?.receive(message) } }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "settings-client")
    }

    private func receive(_ message: JSONRPCPeer.Message) {
        guard let id = message.id, let peer else { return }
        do {
            switch message.method {
            case HostProtocol.Method.initialize:
                try peer.respond(
                    to: id,
                    with: HostInfo(
                        protocolVersion: HostProtocol.version, hostID: hostID, machineName: displayName,
                        hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: epoch,
                        processID: 1, startedAt: .now, channel: "tests"))
            case HostProtocol.Method.listAgents:
                try peer.respond(to: id, with: [HostAgent(id: "fixture", name: "Fixture", state: .stopped)])
            case HostProtocol.Method.listSessions:
                try peer.respond(to: id, with: [HostSessionSummary]())
            case HostProtocol.Method.restartAgent:
                let params = try message.params(as: AgentParams.self)
                restarts.append(params.agentID)
                try peer.respond(to: id, with: HostAgent(id: params.agentID, name: "Fixture", state: .stopped))
            default:
                try peer.respond(to: id, error: .methodNotFound(message.method))
            }
        } catch {
            print("FAIL: fixture response: \(error)")
            exit(1)
        }
    }
}

@main
@MainActor
private struct ComposerSettingsRegression {
    static func main() async {
        do {
            try capturedModels()
            try composeChoicesAndDismissal()
            try keyboardTargets()
            try await restartRouting()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw SettingsFailure(message: message) }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now > deadline { throw SettingsFailure(message: "Timed out") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func capturedModels() throws {
        let options = try GatewayWire.options()
        let settings = ComposerSettings(options)
        guard let model = settings.model else { throw SettingsFailure(message: "No captured model option") }
        guard case .select(_, let wireChoices) = options.first(where: { $0.category == "model" })?.kind else {
            throw SettingsFailure(message: "No wire choices")
        }
        try expect(model.choices == wireChoices.uniqued, "Composer changed captured name/value pairs")
        var sent: String?
        let popover = ComposerSettingsPopover(
            settings: settings, agentName: "Fixture", onSet: { _, value in sent = value })
        let reversedID = "claude-fable-5-dd-5.4-ukiah-edualc/tolipoc"
        popover.choose(.model(reversedID), closing: false)
        try expect(sent == reversedID, "Composer changed the gateway's selection value")
        print("PASS: captured wire models retain name/value pairs through ComposerSettings and selection")
    }

    private static func keyboardTargets() throws {
        let rows = ComposerSettingsPreviewFixtures.rows(agent: false)
        var popover = ComposerSettingsPopover(
            settings: ComposerSettingsPreviewFixtures.codex(), agentName: "Fixture", rows: rows,
            failure: .init(optionID: "model", message: "Try another model", retry: {}), onSet: { _, _ in })
        try expect(popover.sections.flatMap { $0 }.contains(.fastMode), "Fast mode cannot be reached")
        try expect(popover.sections.flatMap { $0 }.contains(.retry), "Retry cannot be reached")
        try expect(
            popover.pageTargets(rows[0]).contains(.command(row: "mode", index: 0)), "Edit Modes cannot be reached")
        let modelPage = ComposerSettingsPopover(
            settings: ComposerSettingsPreviewFixtures.codex(), agentName: "Fixture",
            failure: .init(optionID: "model", message: "Try another model", retry: {}), onSet: { _, _ in },
            page: .model)
        try expect(modelPage.sections.flatMap { $0 }.contains(.retry), "Model page Retry cannot be reached")
        var retried = false
        var restarted = false
        var changed = false
        popover = ComposerSettingsPopover(
            settings: ComposerSettingsPreviewFixtures.codex(), agentName: "Fixture", rows: rows,
            failure: .init(optionID: "model", message: "Try another model", retry: { retried = true }),
            onSet: { _, _ in changed = true })
        popover.choose(.retry, closing: false)
        popover.choose(.fastMode, closing: false)
        try expect(retried && changed, "Auxiliary targets did not activate")
        popover = ComposerSettingsPopover(
            settings: ComposerSettingsPreviewFixtures.codex(), agentName: "Fixture", isStopped: true,
            onRestart: { restarted = true }, onSet: { _, _ in changed = true })
        changed = false
        try expect(popover.sections == [[.restart]], "Stopped settings still offered changes")
        popover.choose(.model("gpt-6-luna"), closing: false)
        popover.choose(.restart, closing: false)
        try expect(restarted && !changed, "Stopped settings changed or Restart failed")
        print("PASS: Fast mode, retry, Edit Modes and Restart have working keyboard targets")
    }

    private static func composeChoicesAndDismissal() throws {
        let app = AppModel.preview(.empty)
        let settings = ComposerSettingsPreviewFixtures.claude()
        app.composeTask.options = [settings.model?.option, settings.effort?.option, settings.autonomy?.option]
            .compactMap { $0 }
        app.composeTask.defaults = ["mode": "bypassPermissions"]
        guard let permissions = settings.autonomy else { throw SettingsFailure(message: "No permissions") }
        app.composeTask.choose(permissions, value: "default")
        app.quickEntry.picker = .agent
        guard let popover = ComposeAgentPicker(model: app).body as? ComposerSettingsPopover,
            let mode = popover.rows.first(where: { $0.id == "compose-mode" })
        else { throw SettingsFailure(message: "Compose lost its Mode row") }
        mode.perform("build")
        try expect(
            ComposerSettings(app.composeTask.options).autonomy?.value == "default",
            "Selecting current Build changed a non-default permission")
        mode.perform("plan")
        popover.onClose()
        app.quickEntry.picker = .agent
        try expect(app.composeTask.choices["mode"] == "plan", "Compose cannot start in Plan")
        guard let updated = ComposeAgentPicker(model: app).body as? ComposerSettingsPopover,
            let updatedMode = updated.rows.first(where: { $0.id == "compose-mode" })
        else { throw SettingsFailure(message: "Compose lost its selected Mode row") }
        try expect(updatedMode.value == "Plan", "Compose did not reflect Plan")
        updatedMode.perform("build")
        try expect(
            ComposerSettings(app.composeTask.options).autonomy?.value == "default",
            "Build broadened permissions after dismissing and reopening the picker")
        popover.onClose()
        try expect(app.quickEntry.picker == nil, "Compose did not wire the dismissal handler")
        print("PASS: Compose offers Plan, restores Build permissions and closes its owning presentation")
    }

    private static func restartRouting() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "composer-settings-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [
                AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true")
            ])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            titles: SessionTitles(), defaults: defaults, catalogURL: nil,
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch)))
        let local = SettingsHost()
        let remote = SettingsHost()
        let info = PeerInfo(name: "Fixture", version: "1", build: "1")
        let localClient = NativeHostClient(transport: local, clientInfo: info)
        let remoteClient = NativeHostClient(transport: remote, clientInfo: info)
        app.connectHost(client: localClient)
        let host = app.hosts.add(
            PairedHost(
                result: LinkPairingResult(
                    hostID: remote.hostID, hostKey: LinkIdentity().publicKey, hostName: "Fixture host",
                    deviceID: UUID(),
                    grants: LinkGrants(), addresses: []), identity: LinkIdentity()))
        host.start(using: remoteClient)
        try await wait { host.isOnline }
        let definition = RemoteHost.definition(from: HostAgent(id: "fixture", name: "Fixture", state: .stopped))
        let summary = HostSessionSummary(
            id: HostSessionID(), agentID: "fixture", agentName: "Fixture",
            agentSessionID: SessionID("fixture"), cwd: "/fixture", phase: .disconnected)
        let session = SessionModel(
            agent: definition, id: SessionID("fixture"), summary: summary,
            client: remoteClient, services: app.sessions.services, promptCapabilities: PromptCapabilities(),
            origin: .user, parent: nil)
        await app.restartAgent(for: session)
        try expect(await remote.restarts == ["fixture"], "Restart missed the task's host")
        try expect(await local.restarts.isEmpty, "Restart reached this Mac for a remote task")
        host.stop()
        await remoteClient.stop()
        await app.restartAgent(for: session)
        try expect(await remote.restarts == ["fixture"], "Unavailable host was restarted")
        try expect(await local.restarts.isEmpty, "Unavailable host fell back to this Mac")
        try expect(
            session.state.items.contains {
                if case .notice(let notice) = $0 { return notice.text.contains("Reconnect the task's host") }
                return false
            }, "Unavailable host did not explain how to reconnect")
        print("PASS: Restart stays on the task's host; unavailable hosts never fall back to this Mac")
    }
}
