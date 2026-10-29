// The runner prepends the existing in-memory host fixture from droid-change-agent.swift.
// Only fixture protocol responses are adapted to report a conservative permission mode.

private actor AgentModelAttachmentGate {
    private var value: PromptAttachment?
    private var continuation: CheckedContinuation<PromptAttachment, Never>?

    func read() async -> PromptAttachment {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }

    func release(_ attachment: PromptAttachment) {
        value = attachment
        continuation?.resume(returning: attachment)
        continuation = nil
    }
}

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
        let domain = ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        do {
            try duplicateModels()
            try await run()
            try await inAppRecovery()
        } catch { print("FAIL: \(error)"); exit(1) }
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
        let commentEditors = DiffCommentsPreviewFixtures.quotes(task: source.clientID)
        source.diffCommentEditors = commentEditors
        source.unresolvedCommentPacket = "Recover this comment packet"

        let attachment = PromptAttachment(
            url: URL(filePath: "/fixture/notes.txt"), content: .text("Fixture"), byteCount: 7)
        source.attachments = [attachment]
        let reads = source.attachmentReads
        reads.begin(2, in: source)
        let firstRead = AgentModelAttachmentGate()
        let secondRead = AgentModelAttachmentGate()
        let firstFile = PromptAttachment(
            url: URL(filePath: "/fixture/first.txt"), content: .text("First"), byteCount: 5)
        let secondFile = PromptAttachment(
            url: URL(filePath: "/fixture/second.txt"), content: .text("Second"), byteCount: 6)
        let readingFirst = Task { try reads.complete(await firstRead.read()) }
        let readingSecond = Task { try reads.complete(await secondRead.read()) }
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
            target.diffCommentEditors == commentEditors
                && target.unresolvedCommentPacket == "Recover this comment packet"
                && source.diffCommentEditors.isEmpty && source.unresolvedCommentPacket == nil,
            "Comment editor or recovery ownership was lost during model selection")
        try require(
            target.cwd == source.cwd && source.isEarlierConversation && app.ordering.isPinned(target.key),
            "Task moved or duplicated")
        try require(ComposerSettings(target.configOptions).model?.value == "large", "Exact model not confirmed")
        try require(ComposerSettings(target.configOptions).autonomy?.value == "read-only", "Permissions broadened")
        try require(tripwire.calls.isEmpty && hooks == 1, "Preparation allocated a worktree or duplicated task hooks")
        await firstRead.release(firstFile)
        try await readingFirst.value
        try require(
            target.attachments == [attachment, firstFile] && source.attachments.isEmpty,
            "A suspended attachment read landed on the earlier conversation")
        target.draft = "Draft edited after selection"
        first.undo()
        try require(app.selection == source.key && !source.isEarlierConversation, "Undo didn't restore source identity")
        try require(
            source.draft == "Draft edited after selection" && source.attachments == [attachment, firstFile],
            "Undo lost current edits")
        try require(await process.accepted.isEmpty, "Undo submitted a prompt")
        try require(
            source.diffCommentEditors == commentEditors
                && source.unresolvedCommentPacket == "Recover this comment packet"
                && target.diffCommentEditors.isEmpty && target.unresolvedCommentPacket == nil,
            "Undo lost comment editor or recovery ownership")
        source.diffCommentEditors = []
        source.unresolvedCommentPacket = nil
        await secondRead.release(secondFile)
        try await readingSecond.value
        try require(
            source.attachments == [attachment, firstFile, secondFile] && reads.count == 0,
            "Pending reads didn't follow Undo back to the visible draft")
        print("PASS: exact model, permission preservation, no working prompt, one task, drafts and Undo")
        print("PASS: suspended attachment reads follow the draft through selection and Undo")

        experiments.set(false, for: .composerNext)
        let command = NativeCommand.changeAgent(model: app)
        let context = CommandContext(session: source)
        try require(command.isAvailable(context), "Switch Agent is missing with Fine print off")
        command.perform(context)
        try require(source.isAgentPickerRequested && source.isModelPickerRequested, "Command missed the Agent section")
        try require(app.changingAgent == nil, "Legacy composer opened a confirmation sheet")
        source.isAgentPickerRequested = false
        source.isModelPickerRequested = false
        app.switchAgent(to: choice.agent, for: source)
        guard let legacy = source.modelChange else { throw ChangeFailure("No direct agent choice") }
        try await wait("legacy agent prepared") { legacy.stage == .applied || legacy.stage == .failed }
        try require(legacy.stage == .applied, legacy.error ?? "Direct agent choice failed")
        guard let selected = app.selection, let legacyTarget = app.sessions.session(selected) else {
            throw ChangeFailure("No legacy target")
        }
        try require(legacyTarget.agent.id == choice.agent, "Agent choice did not change harness")
        try require(ComposerSettings(legacyTarget.configOptions).model?.value == "small", "Agent default was not used")
        try require(
            legacyTarget.draft == source.draft || legacyTarget.draft == "Draft edited after selection", "Draft lost")
        try require(await process.accepted.isEmpty, "Direct agent choice submitted a working prompt")
        legacy.undo()
        try require(
            app.selection == source.key && source.attachments.count == 3, "Legacy Undo lost the task or attachments")
        experiments.set(true, for: .composerNext)
        print("PASS: Switch Agent command, default model, invisible handoff and Undo with Fine print off")

        source.phase = .prompting
        source.lastStopReason = nil
        app.chooseAgentModel(choice, for: source)
        guard let pending = source.modelChange else { throw ChangeFailure("No waiting choice") }
        try await wait("waiting state") { pending.stage == .waiting }
        let starts = await process.started.count
        let waitingDraft = source.draft
        await source.submit(.queue)
        let promptsWhileWaiting = await process.accepted
        try require(
            source.draft == waitingDraft && promptsWhileWaiting.isEmpty,
            "Draft submission bypassed a pending model choice")
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
        let reverse = app.agentModels(for: current).first { $0.agent == source.agent.id }
        try require(
            reverse != nil && reverse?.unavailable == nil,
            "A prepared continuation cannot choose another agent before sending")
        let userText = "Only answer this explicit message"
        _ = try await current.submit(userText, attaching: current.attachments, .queue)
        let sent = await process.accepted
        try require(sent.count == 1 && sent[0].text == userText, "Context became an extra visible message")
        try require(
            sent[0].attachments.map(\.name).contains(firstFile.name),
            "Outbound message omitted the attachment that finished after selection")
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
        try require(reopened.context(for: source.key) == "Context fixture", "A later selection lost earlier context")
        print(
            "PASS: locally prepared context survives relaunch, is consumed once and remains available to later choices")
        await client.stop()
    }

    static func duplicateModels() throws {
        let settings = ComposerSettings(try GatewayWire.options())
        let catalog =
            settings.model?.choices.map {
                ComposerAgentModel(
                    agent: .init(rawValue: "fixture"), agentName: "Fixture", choice: $0, kind: .model($0.value))
            } ?? []
        let groups = Dictionary(grouping: catalog, by: { $0.choice.displayName }).values.filter { $0.count > 1 }
        try require(!groups.isEmpty, "Captured gateway lost its duplicate names")
        for group in groups {
            let details = group.compactMap { $0.distinction(in: catalog) }
            try require(Set(details).count == group.count, "Combined rows cannot distinguish captured same-name models")
            for row in group {
                guard let detail = row.distinction(in: catalog) else { throw ChangeFailure("No distinction") }
                try require(
                    row.accessibleLabel(in: catalog).contains(detail), "VoiceOver omitted the distinguishing identity")
            }
        }
        print("PASS: captured duplicate model names have visible and accessible distinctions")
    }

    static func inAppRecovery() async throws {
        guard let script = ProcessInfo.processInfo.environment["NATIVE_AGENT_MODEL_FIXTURE_SCRIPT"] else {
            throw ChangeFailure("No in-app fixture script")
        }
        for scenario in ["draft", "empty", "repeated"] {
            let draft = scenario == "empty" ? "" : "Unsent draft survives"
            let scratch = FileManager.default.temporaryDirectory.appending(path: "agent-model-in-app-\(UUID())")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let defaults = PreviewUserDefaults()
            let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
            experiments.set(true, for: .changeAgent)
            experiments.set(true, for: .composerNext)
            let manifest = PluginManifest(
                id: "in-app-fixture", name: "In-app fixture",
                agents: [
                    AgentManifest(
                        id: "fixture", name: "Fixture", command: "/usr/bin/python3",
                        args: [
                            script,
                            "--kind", "source", "--store", scratch.appending(path: "source").path,
                            "--project", scratch.path,
                        ]),
                    AgentManifest(
                        id: "target", name: "Target", command: "/usr/bin/python3",
                        args: [
                            script,
                            "--kind", "target", "--store", scratch.appending(path: "agent").path,
                            "--project", scratch.path, "--reject-unsent-load",
                        ]),
                ])
            func launch() -> AppModel {
                AppModel(
                    plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
                    titles: SessionTitles(), defaults: defaults,
                    catalogURL: scratch.appending(path: "catalog.json"), experiments: experiments)
            }
            let first = launch()
            defer { first.stopAgents() }
            _ = await first.checkForAgents()
            let project = first.projects.add(scratch)
            _ = await first.ensureRunning(.init(rawValue: "fixture"))
            let sourceSettings = ComposerSettingsPreviewFixtures.claude(mode: "default")
            let sourceOptions = [sourceSettings.model?.option, sourceSettings.autonomy?.option].compactMap { $0 }
            guard
                let source = SessionModel.preview(
                    in: first, agent: "fixture", id: "model-source", cwd: scratch.path,
                    configOptions: sourceOptions)
            else { throw ChangeFailure("No in-app source") }
            source.previewExchange("Keep this task", reply: "Recorded progress before changing the agent")
            first.catalog.add(
                SessionInfo(sessionId: source.id, cwd: scratch.path), for: source.agent.id, in: project.id)
            first.selection = source.key
            source.draft = draft
            let choice = ComposerAgentModel(
                agent: .init(rawValue: "target"), agentName: "Target",
                choice: .init(value: "gpt-6-sol", name: "6 Sol"), kind: .model("gpt-6-sol"))
            first.chooseAgentModel(choice, for: source)
            guard let change = source.modelChange else { throw ChangeFailure("No in-app choice") }
            try await wait("in-app commit") { change.stage == .applied || change.stage == .failed }
            try require(change.stage == .applied, change.error ?? "In-app choice failed")
            guard let selected = first.selection, let prepared = first.session(selected),
                let runtime = first.runtimes[prepared.agent.id]
            else { throw ChangeFailure("No selected in-app task") }
            if scenario == "repeated" {
                let next = ComposerAgentModel(
                    agent: .init(rawValue: "fixture"), agentName: "Fixture",
                    choice: .init(value: "sonnet", name: "Sonnet 5.5"), kind: .model("sonnet"))
                first.chooseAgentModel(next, for: prepared)
                guard let second = prepared.modelChange else { throw ChangeFailure("No repeated choice") }
                try await wait("repeated unsent choice") { second.stage == .applied || second.stage == .failed }
                try require(second.stage == .applied, second.error ?? "Repeated choice failed")
            } else {
                first.sessions.remove(prepared)
                guard let recovered = await first.replaceEmptySession(prepared, on: runtime) else {
                    throw ChangeFailure("Unsent choice failed crash recreation")
                }
                try require(
                    !first.unsentSessions.contains(selected) && first.unsentSessions.contains(recovered.key),
                    "Crash recreation left the recovery record under its old key")
            }
            guard let old = first.selection else { throw ChangeFailure("No selected continuation") }
            first.keepDrafts()
            first.stopAgents()
            try Data("agent-full-access".utf8).write(to: scratch.appending(path: "agent/default-mode"))
            let again = launch()
            defer { again.stopAgents() }
            _ = await again.checkForAgents()
            try require(again.catalog.contains(old), "An empty unsent model selection was dropped at launch")
            again.selection = old
            await again.loadSession(old)
            guard let key = again.selection, let reopened = again.session(key) else {
                throw ChangeFailure("In-app unsent choice couldn't reopen")
            }
            try require(
                key != old && reopened.draft == draft, "Recovery lost the draft or reused an unsaved conversation")
            if scenario == "repeated" {
                guard let undo = reopened.modelChange else { throw ChangeFailure("No restored repeated Undo") }
                undo.undo()
                try await wait("Undo recreates unsent predecessor") { undo.stage == .reversed }
                guard let undoneKey = again.selection, let undone = again.session(undoneKey) else {
                    throw ChangeFailure("No restored predecessor")
                }
                try require(
                    undoneKey.agent.rawValue == "target" && undoneKey != selected && undone.draft == draft,
                    "Repeated Undo lost the recreated predecessor or current draft")
                again.keepDrafts()
                again.stopAgents()
                let third = launch()
                defer { third.stopAgents() }
                _ = await third.checkForAgents()
                third.selection = undoneKey
                await third.loadSession(undoneKey)
                try require(
                    third.selection.flatMap { third.session($0)?.draft } == draft,
                    "Undo's recreated predecessor did not survive another launch")
                continue
            }
            try require(
                ComposerSettings(reopened.configOptions).model?.value == "gpt-6-sol"
                    && ComposerSettings(reopened.configOptions).autonomy?.value == "read-only",
                "Recovery lost confirmed settings")
            try require(
                again.earlierConversations.conversation(before: key) == source.key,
                "Recovery lost the earlier conversation")
            try require(reopened.modelChange?.canUndo == true, "Recovery lost the reversible receipt")
            _ = try await reopened.submit("Continue", .queue)
            try await wait("first recovered turn ends") { reopened.phase == .idle }
            _ = try await reopened.submit("Again", .queue)
            try await wait("second recovered turn ends") { reopened.phase == .idle }
            let deliveries = try JSONDecoder().decode(
                [Bool].self,
                from: Data(contentsOf: scratch.appending(path: "agent/context-deliveries.json")))
            try require(deliveries == [true, false], "Recovered context didn't arrive exactly once")
            again.stopAgents()
        }
        print(
            "PASS: in-app crash/relaunch restores unsent choices; repeated Undo follows recreated predecessors")
    }

}
