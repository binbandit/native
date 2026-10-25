import ACP
import Foundation
import NativeCommands
import NativeHostClient
import NativeHostProtocol

@testable import Native

/// Holds session creation so navigation and retries can be checked against real host messages.
private actor QuickEntryHost: HostTransport {
    nonisolated var displayName: String { "Quick Entry fixture" }
    var peer: JSONRPCPeer?
    var pending: (RequestID, NewSessionParams)?
    var created = 0
    var prompts: [String] = []
    var holdsListing = false
    var listingRequest: RequestID?
    let agent = HostAgent(
        id: "fake", name: "Fake Agent", state: .ready,
        initialize: .object([
            "protocolVersion": .number(1),
            "agentCapabilities": .object(["sessionCapabilities": .object(["list": .object([:])])]),
        ]))

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(
            channel: ByteChannel.socket(hostEnd, label: "quick-entry-host"), label: "quick-entry-host"
        ) {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch { print("Fixture request failed: \(error)") }
                }
            }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "quick-entry-client")
    }

    func receive(_ message: JSONRPCPeer.Message) throws {
        guard let id = message.id, let peer else { return }
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: HostID(), machineName: displayName,
                    hostInfo: PeerInfo(name: "Native Host", version: "1", build: "1"), epoch: UUID(),
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.syncAgents:
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.listAgents:
            try peer.respond(to: id, with: [agent])
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: [HostSessionSummary]())
        case HostProtocol.Method.listAgentSessions:
            if holdsListing {
                listingRequest = id
            } else {
                try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
            }
        case HostProtocol.Method.startAgent:
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.newSession:
            pending = (id, try message.params(as: NewSessionParams.self))
        case HostProtocol.Method.prompt:
            let prompt = try message.params(as: PromptParams.self)
            prompts.append(prompt.text)
            try peer.notify(
                HostProtocol.Method.sessionEvent,
                SessionEventNotification(
                    sessionID: prompt.sessionID,
                    event: HostEvent(seq: 1, payload: .prompt(PromptEcho(text: prompt.text, steered: false)))))
            try peer.respond(to: id, with: PromptResult(delivery: .prompted))
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }

    func holdListing() { holdsListing = true }

    func releaseListing() throws {
        holdsListing = false
        if let id = listingRequest {
            try peer?.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        }
        listingRequest = nil
    }

    func complete(failing: Bool = false) throws {
        guard let (id, params) = pending, let peer else { throw CheckFailure("No pending session") }
        pending = nil
        if failing {
            try peer.respond(to: id, error: RPCError(code: -32603, message: "Fixture startup failure"))
        } else {
            created += 1
            try peer.respond(
                to: id,
                with: HostSessionSummary(
                    id: params.sessionID ?? HostSessionID(), agentID: "fake", agentName: "Fake Agent",
                    agentSessionID: SessionID("quick-entry-\(created)"), cwd: params.cwd, phase: .idle))
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
@MainActor
private struct QuickEntryRegression {
    static func main() async {
        do {
            // The switch is process-local, preserving the isolated instance's saved preferences.
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["experiment.NativeComposeTask"] = true
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            try await check()
            print("PASS: Quick Entry preserves drafts, selection, context, expansion and failed starts")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func check() async throws {
        let host = QuickEntryHost()
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "quick-entry-fixture", name: "Quick Entry fixture",
            agents: [AgentManifest(id: "fake", name: "Fake Agent", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil)
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        let folder = FileManager.default.temporaryDirectory.appending(path: "quick-entry-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = app.projects.add(folder)
        app.focusProject(project.id)
        let entry = app.quickEntry
        app.showQuickEntry(selection: "first line\nsecond line")
        entry.draft = "Keep this draft"
        let message = entry.message
        try require(message.hasSuffix("> first line\n> second line"), "Selection was not quoted")
        entry.dismiss()
        app.showQuickEntry(selection: "Do not replace retained context")
        try require(entry.message == message, "Reopening replaced the draft or context")
        let createdWhileDrafting = await host.created
        try require(app.startingTasks.isEmpty && createdWhileDrafting == 0, "Drafting created a task")

        app.startQuickEntry(open: false)
        guard let background = entry.lastStartedTask else { throw CheckFailure("No background start") }
        try require(app.selection != background.id, "Background start changed selection")
        try require(!entry.isPresented && entry.draft.isEmpty && entry.context == nil, "Start did not clear the panel")
        try await wait { await host.pending != nil }
        app.focusProject(project.id)
        let selectedWhileStarting = app.selection
        try await host.complete()
        try await wait { await host.prompts.count == 1 }
        try require(app.selection == selectedWhileStarting, "Background completion stole selection")
        try require(entry.taskOpenRequests == 0, "Background start requested foreground navigation")
        try require(await host.prompts == [message], "The first message lost its selection context")
        app.openQuickEntryTask()
        try require(app.selection == background.openedSession, "Open did not find the completed task")
        try require(entry.taskOpenRequests == 1, "Open did not request a visible destination")

        app.showQuickEntry()
        entry.draft = "Keep this while changing folders"
        let previousSelection = app.selection
        let secondFolder = folder.appending(path: "second")
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        await host.holdListing()
        let addingFolder = Task { await app.addQuickEntryProject(secondFolder) }
        try await wait { await host.listingRequest != nil }
        try require(entry.project != project.id, "The chosen folder did not replace the draft's project")
        try require(
            entry.project.flatMap(app.projects.project)?.url == secondFolder, "The draft targets the wrong folder")
        try require(app.selection == previousSelection, "Choosing a folder navigated away from the underlying task")
        try require(entry.draft == "Keep this while changing folders", "Choosing a folder lost the draft")
        try await host.releaseListing()
        await addingFolder.value
        app.chooseQuickEntryProject(project.id)

        app.showQuickEntry()
        entry.draft = "Start and open"
        app.startQuickEntry(open: true)
        guard let foreground = app.startingTasks.first else { throw CheckFailure("No foreground start") }
        try require(app.selection == foreground.id, "Start and open did not select its placeholder")
        try require(entry.taskOpenRequests == 2, "Foreground start did not request a visible destination")
        try await wait { await host.pending != nil }
        try await host.complete()
        try await wait { await host.prompts.count == 2 }
        try require(app.selection == foreground.openedSession, "Foreground completion did not select the task")

        app.showQuickEntry()
        entry.draft = "Expand without sending"
        app.expandQuickEntry()
        try require(entry.taskOpenRequests == 3, "Expand did not request a visible destination")
        try require(app.composeTask.isPresented, "Expand did not show Compose")
        try require(app.composeTask.editor?.draft == "Expand without sending", "Expand lost the draft")
        try require(app.startingTasks.isEmpty, "Expand created a task before Start")
        try require(await host.pending == nil, "Expand contacted the agent")
        try require(await host.prompts.count == 2, "Expand submitted the draft")
        app.closeComposeTask()
        app.expandQuickEntry()
        try require(app.composeTask.editor?.draft == "Expand without sending", "Reopening Compose lost the draft")
        guard let editor = app.composeTask.editor else { throw CheckFailure("No Compose editor") }
        app.composeTask.workspace = .newWorktree
        app.composeTask.beginWorkspaceSelection()
        app.composeTask.workspaceSelection = .project
        app.composeTask.cancelWorkspaceSelection()
        try require(app.composeTask.workspace == .newWorktree, "Cancel changed the addressed workspace")
        app.composeTask.beginWorkspaceSelection()
        app.composeTask.workspaceSelection = .project
        app.composeTask.applyWorkspaceSelection()
        try require(app.composeTask.workspace == .project, "Use Workspace did not commit the selection")
        let draftContext = CommandContext(composeDraft: app.composeTask.commandDraft)
        for id in [CommandID.composerAttachFiles, .composerFocus, .sessionChooseModel] {
            guard let command = NativeCommand.composer.first(where: { $0.id == id }) else {
                throw CheckFailure("Missing draft command")
            }
            try require(command.isAvailable(draftContext), "A draft command was unavailable")
            command.perform(draftContext)
        }
        try require(
            editor.isAttachmentPickerRequested && editor.isModelPickerRequested,
            "Draft commands did not reach the editor")
        editor.isAttachmentPickerRequested = false
        editor.isModelPickerRequested = false
        for command in NativeCommand.composer where [.sessionStop, .sessionChangeWorkspace].contains(command.id) {
            try require(!command.isAvailable(draftContext), "A task-only command was enabled before Start")
        }
        editor.attachments = [
            PromptAttachment(url: folder.appending(path: "missing-file"), content: .reference, byteCount: nil)
        ]
        app.startComposeTask()
        try require(app.startingTasks.isEmpty && entry.failure != nil, "Missing attachment did not block Start")
        editor.attachments = []
        app.composeTask.options = ComposeTaskPreviewFixtures.options
        let addressed = Dictionary(
            app.composeTask.options.compactMap { option -> (String, String)? in
                guard let category = option.category, case .select(let value, _) = option.kind else { return nil }
                return (category, value)
            }, uniquingKeysWith: { first, _ in first })
        app.composeTask.choices = [:]
        app.startComposeTask()
        guard let composed = app.composeTask.starting else { throw CheckFailure("Compose did not create a task") }
        try require(composed.configChoices == addressed, "Start omitted the displayed defaults")
        // This fixture agent has no settings; clear the captured values after testing the snapshot.
        composed.configChoices = [:]
        let startingContext = CommandContext(composeDraft: app.composeTask.commandDraft)
        for command in NativeCommand.composer
        where [CommandID.composerAttachFiles, .composerFocus, .sessionChooseModel].contains(command.id) {
            try require(!command.isAvailable(startingContext), "A starting letter still exposed editing commands")
        }
        try require(composed.draft == "Expand without sending", "Start did not snapshot the draft")
        app.startComposeTask()
        try require(app.startingTasks.count == 1, "A second Start duplicated the task")
        try await wait { await host.pending != nil }
        try await host.complete()
        try await wait { await host.prompts.count == 3 }
        app.composeTask.stage = .settled
        try await wait { app.composeCanRevealTask }
        app.finishComposeTransition()
        try require(!app.composeTask.isPresented, "The transition did not reveal the task")
        try require(entry.draft.isEmpty, "Start retained a duplicate draft")
        if let key = composed.openedSession, let session = app.session(key) {
            let unavailable = StartingTask(
                project: project.id, agent: editor.agent, isAgentPicked: true, workspaceLabel: "Fixture")
            unavailable.isSendRequested = true
            unavailable.configChoices = ["model": "no-longer-offered"]
            await app.applyComposeChoices(of: unavailable, to: session)
            try require(!unavailable.isSendRequested, "An unavailable setting allowed the prompt to send")
        } else {
            throw CheckFailure("The composed task was not registered")
        }

        let empty = SessionModel(
            agent: editor.agent, id: SessionID("compose-handoff-fixture"), cwd: folder,
            connection: nil, services: app.sessions.services, supportsSteering: false,
            promptCapabilities: PromptCapabilities(), phase: .idle)
        app.sessions.register(empty)
        let handoff = StartingTask(
            project: project.id, agent: editor.agent, isAgentPicked: true, workspaceLabel: "Fixture")
        handoff.openedSession = empty.key
        handoff.isSendRequested = true
        handoff.composeSubmission = .sent
        app.composeTask.starting = handoff
        app.composeTask.stage = .settled
        app.composeTask.isPresented = true
        app.finishComposeTransition()
        try require(app.composeTask.isPresented, "Handoff exposed the empty welcome page")
        empty.state.appendUserMessage("Keep the first message visible")
        app.finishComposeTransition()
        try require(!app.composeTask.isPresented, "Handoff did not reveal the real message")
        app.sessions.remove(empty)

        app.expandQuickEntry()
        app.composeTask.editor?.draft = "Cancel without sending"
        app.startComposeTask()
        try await wait { await host.pending != nil }
        app.cancelComposeStart()
        try require(app.composeTask.stage == .writing, "Cancel did not return to the letter")
        try require(app.composeTask.editor?.draft == "Cancel without sending", "Cancel lost the draft")
        try await host.complete()
        try await wait { app.startingTasks.isEmpty }
        try require(await host.prompts.count == 3, "Cancelled Start sent a message")
        app.closeComposeTask()

        app.showQuickEntry()
        entry.draft = "Retry me"
        app.startQuickEntry(open: false)
        guard let failed = entry.lastStartedTask else { throw CheckFailure("No failing start") }
        try await wait { await host.pending != nil }
        try await host.complete(failing: true)
        try await wait { failed.failure != nil }
        try require(failed.draft == "Retry me", "Failed startup lost the message")
        let retry = Task { await app.retry(failed) }
        try await wait { await host.pending != nil }
        try await host.complete()
        await retry.value
        try await wait { await host.prompts.count == 4 }
        try require(await host.prompts.last == "Retry me", "Retry did not send the retained message")

        app.showQuickEntry()
        entry.draft = "Keep while unavailable"
        entry.project = nil
        app.startQuickEntry(open: false)
        try require(entry.isPresented && entry.picker == .project, "Missing project did not stay editable")
        entry.project = project.id
        entry.device = .remote(NativeHostProtocol.HostID())
        app.startQuickEntry(open: false)
        try require(entry.isPresented && entry.picker == .device, "Unavailable device did not stay editable")
        entry.device = .thisMac
        app.expandQuickEntry()
        let heldDevice = SessionDevice.remote(NativeHostProtocol.HostID())
        entry.device = heldDevice
        entry.previewDeviceOptions = [
            .init(
                device: heldDevice, name: "elara", availability: .offline(reason: "Fixture offline"),
                checkout: .present(path: "native"))
        ]
        app.composeTask.options = ComposeTaskPreviewFixtures.options
        let heldAddress = app.composeTask.addressedChoices
        app.holdComposeTask()
        try require(app.composeTask.isHeld, "Hold did not retain the offline task")
        let heldContext = CommandContext(composeDraft: app.composeTask.commandDraft)
        for command in NativeCommand.composer
        where [CommandID.composerAttachFiles, .composerFocus, .sessionChooseModel].contains(command.id) {
            try require(!command.isAvailable(heldContext), "A held letter still exposed editing commands")
        }
        let restoredHold = ComposeTaskModel(defaults: defaults)
        try require(restoredHold.heldDraft?.text == "Keep while unavailable", "Hold was not durable")
        try require(restoredHold.heldDraft?.device == heldDevice, "Hold changed the destination")
        try require(restoredHold.heldDraft?.choices == heldAddress, "Hold omitted the displayed defaults")
        app.closeComposeTask()
        app.expandQuickEntry()
        try require(app.composeTask.editor?.draft == "Keep while unavailable", "Opening Hold lost its draft")
        app.composeTask.cancelHold()
        try require(app.composeTask.commandDraft != nil, "Cancel Hold did not restore draft commands")
        try require(ComposeTaskModel(defaults: defaults).heldDraft == nil, "Cancel Hold did not clear persistence")
        app.closeComposeTask()
        entry.previewDeviceOptions = nil
        app.showQuickEntry()
        entry.device = .thisMac
        try FileManager.default.removeItem(at: folder)
        app.startQuickEntry(open: false)
        try require(entry.isPresented && entry.failure != nil, "Missing folder did not stay editable")
        try require(entry.draft == "Keep while unavailable", "Validation discarded the draft")
        try require(app.startingTasks.isEmpty, "Validation created a placeholder")
        var options = ComposeTaskPreviewFixtures.options
        AgentSessionDefaults.remember(options, for: editor.agent.id, isNew: true, defaults: defaults)
        if let index = options.firstIndex(where: { $0.category == "mode" }),
            case .select(_, let offered) = options[index].kind
        {
            options[index].kind = .select(currentValue: "agent-full-access", options: offered)
        }
        AgentSessionDefaults.remember(options, for: editor.agent.id, defaults: defaults)
        let newOptions = AgentSessionDefaults.offeredOptions(for: editor.agent.id, defaults: defaults)
        try require(
            ComposerSettings(newOptions).autonomy?.value == "workspace-write",
            "A prior task's permissions became the default")
        await client.stop()
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message) }
    }

    static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw CheckFailure("Timed out waiting for the expected state") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
