// The runner prepends the existing in-memory host fixture from droid-change-agent.swift.
// Only fixture protocol responses are adapted to report a conservative permission mode.

@main
@MainActor
private struct AgentModelChangeRegression {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw ChangeFailure(message) }
    }

    static func wait(_ message: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw ChangeFailure("Timed out: \(message)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func main() async {
        do { try await run() } catch { print("FAIL: \(error)"); exit(1) }
    }

    static func run() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "agent-model-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .changeAgent)
        experiments.set(true, for: .composerNext)
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [
                AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true"),
                AgentManifest(id: "droid", name: "Droid", command: "/usr/bin/true"),
            ])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil, experiments: experiments)
        _ = app.runtimes.sync()
        let process = ChangeHost(folder: "/fixture", source: SessionID("source"))
        let link = ChangeLink(process)
        let client = NativeHostClient(transport: link, clientInfo: .init(name: "Fixture", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        for agent in await process.agents { app.runtime(.init(rawValue: agent.id))?.apply(agent) }
        let project = app.projects.add(URL(filePath: "/fixture"))
        let summary = await process.summaries[0]
        guard let definition = app.plugins.agent(.init(rawValue: "fixture")) else { throw ChangeFailure("No agent") }
        let source = SessionModel(
            agent: definition, id: SessionID("source"), summary: summary, client: client,
            services: app.sessions.services, promptCapabilities: .init(), origin: .user, parent: nil)
        app.sessions.register(source)
        source.previewExchange("Fix the login form", reply: "The form now keeps its draft.")
        source.state.configOptions =
            ComposerPreviewFixtures.decode(
                """
                [{"id":"mode","name":"Permissions","category":"mode","type":"select","currentValue":"default",
                  "options":[{"value":"default","name":"Before any change"}]},
                 {"id":"model","name":"Model","category":"model","type":"select","currentValue":"small",
                  "options":[{"value":"small","name":"Small"}]}]
                """) ?? []
        app.catalog.add(SessionInfo(sessionId: source.id, cwd: "/fixture"), for: source.agent.id, in: project.id)
        app.selection = source.key
        app.ordering.pin(source.key)
        source.draft = "Keep my unsent draft"
        let attachment = PromptAttachment(
            url: URL(filePath: "/fixture/notes.txt"), content: .text("Fixture"), byteCount: 7)
        source.attachments = [attachment]
        let tripwire = WorkspaceTripwire()
        app.taskWorkspaces = tripwire
        var hooks = 0
        app.sessionHooks.taskStarted = { _, earlier in
            if earlier === source { hooks += 1 }
        }
        let choice = ComposerAgentModel(
            agent: .init(rawValue: "droid"), agentName: "Droid",
            choice: .init(value: "large", name: "Large"), kind: .model("large"))
        try require(
            app.agentModels(for: source).contains { $0.agent.rawValue == "droid" && $0.kind == .load },
            "An unreported model catalog was invented")
        let initialStarts = await process.started
        let initialPrompts = await process.accepted
        try require(initialStarts.isEmpty && initialPrompts.isEmpty, "Opening the list did work")
        app.chooseAgentModel(choice, for: source)
        guard let first = source.modelChange else { throw ChangeFailure("No pending choice") }
        do {
            try await wait("model prepared") { first.stage == .applied || first.stage == .failed }
        } catch {
            print(
                "Fixture stage: \(first.stage), calls: \(await process.calls), starts: \(await process.started.count)")
            throw error
        }
        try require(first.stage == .applied, first.error ?? "Not applied")
        guard let key = app.selection, let target = app.sessions.session(key) else { throw ChangeFailure("No target") }
        try require(await process.accepted.isEmpty, "Choosing a model submitted a working prompt")
        try require(target.draft == "Keep my unsent draft" && target.attachments == [attachment], "Draft was lost")
        try require(
            target.cwd == source.cwd && source.isEarlierConversation && app.ordering.isPinned(target.key),
            "Task moved or duplicated")
        try require(ComposerSettings(target.configOptions).model?.value == "large", "Exact model not confirmed")
        try require(ComposerSettings(target.configOptions).autonomy?.value == "read-only", "Permissions broadened")
        try require(tripwire.calls.isEmpty && hooks == 1, "Preparation allocated a worktree or duplicated task hooks")
        target.draft = "Draft edited after selection"
        first.undo()
        try require(app.selection == source.key && !source.isEarlierConversation, "Undo didn't restore source identity")
        try require(
            source.draft == "Draft edited after selection" && source.attachments == [attachment],
            "Undo lost current edits")
        try require(await process.accepted.isEmpty, "Undo submitted a prompt")
        print("PASS: exact model, permission preservation, no working prompt, one task, drafts and Undo")

        source.phase = .prompting
        source.lastStopReason = nil
        app.chooseAgentModel(choice, for: source)
        guard let pending = source.modelChange else { throw ChangeFailure("No waiting choice") }
        try await wait("waiting state") { pending.stage == .waiting }
        let starts = await process.started.count
        pending.cancel()
        source.phase = .idle
        try await Task.sleep(for: .milliseconds(40))
        try require(await process.started.count == starts, "Cancelled waiting selection still started an agent")
        print("PASS: busy selection waits without stopping, and cancellation starts nothing")

        let unavailable = ComposerAgentModel(
            agent: choice.agent, agentName: choice.agentName,
            choice: .init(value: "removed-model", name: "Removed Model"), kind: .model("removed-model"))
        app.chooseAgentModel(unavailable, for: source)
        guard let rejected = source.modelChange else { throw ChangeFailure("No failed selection") }
        try await wait("missing model rejected") { rejected.stage == .failed }
        try require(
            app.selection == source.key && source.draft == "Draft edited after selection",
            "Failure lost source or draft")
        try require(await process.accepted.isEmpty, "Failed model selection submitted a prompt")
        print("PASS: missing offered model leaves the source and draft intact")

        app.modelChangeGoalBlock = { _ in "Clear this task's goal before choosing another agent." }
        let beforeBlocked = await process.started.count
        app.chooseAgentModel(choice, for: source)
        try await wait("goal blocks selection") { source.modelChange?.stage == .failed }
        try require(await process.started.count == beforeBlocked, "A blocked goal still prepared a replacement")
        app.modelChangeGoalBlock = { _ in nil }
        source.phase = .prompting
        source.lastStopReason = nil
        app.chooseAgentModel(choice, for: source)
        source.state.apply(.agentMessageChunk(ContentChunk(content: .text("Final context at the idle boundary"))))
        source.lastStopReason = .endTurn
        source.phase = .idle
        guard let applied = source.modelChange else { throw ChangeFailure("No new choice") }
        try await wait("second selection") { applied.stage == .applied || applied.stage == .failed }
        try require(applied.stage == .applied, applied.error ?? "Second selection failed")
        guard let currentKey = app.selection, let current = app.sessions.session(currentKey) else {
            throw ChangeFailure("No current task")
        }
        try require(
            app.sessions.services.modelContinuations.context(for: current.key)?.contains(
                "Final context at the idle boundary") == true,
            "Busy selection captured stale context")
        let userText = "Only answer this explicit message"
        _ = try await current.submit(userText, .queue)
        let sent = await process.accepted
        try require(sent.count == 1 && sent[0].text == userText, "Context became an extra visible message")
        let blocks = sent[0].content ?? []
        try require(blocks.count >= 2, "Next explicit message omitted context")
        try require(!applied.canUndo, "Undo promised to unsend an accepted message")
        try require(
            app.sessions.services.modelContinuations.take(for: current.key) == nil, "Context would repeat automatically"
        )
        print("PASS: next explicit message carries context once with unchanged user echo")

        let store = AgentModelContinuations(defaults: defaults)
        store.prepare("Context fixture", for: source.key)
        let reopened = AgentModelContinuations(defaults: defaults)
        try require(
            reopened.take(for: source.key) != nil && reopened.take(for: source.key) == nil,
            "Pending context didn't survive reload or was reused")
        print("PASS: locally prepared context survives relaunch and is consumed once")
        await client.stop()
    }

}
