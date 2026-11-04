import ACP
import Experiments
import Foundation
import Synchronization
import TextInput

@testable import Native

private struct RowCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A connected ACP agent whose complete settings replies are released by the test.
nonisolated private final class RowRequests: Sendable {
    private let values = Mutex<[JSONValue]>([])
    var all: [JSONValue] { values.withLock { $0 } }
    func append(_ value: JSONValue) { values.withLock { $0.append(value) } }
}

nonisolated private final class RowSettingsAgent: Sendable {
    let connection: ACPConnection
    private let requests = RowRequests()
    private let output: FileHandle

    init() async {
        let toAgent = Pipe()
        let toClient = Pipe()
        output = toClient.fileHandleForWriting
        connection = ACPConnection(
            reading: toClient.fileHandleForReading, writing: toAgent.fileHandleForWriting,
            onEvent: { _ in })
        let input = toAgent.fileHandleForReading
        let requests = requests
        Thread.detachNewThread {
            var pending = Data()
            while true {
                let data = input.availableData
                guard !data.isEmpty else { return }
                pending.append(data)
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    if let request = try? JSONDecoder().decode(JSONValue.self, from: line) {
                        requests.append(request)
                    }
                }
            }
        }
        await connection.start()
    }

    var received: [JSONValue] { requests.all }

    func reply(_ request: JSONValue, options: [JSONValue]) throws {
        let id = String(decoding: try JSONEncoder().encode(request["id"]), as: UTF8.self)
        let snapshot = String(decoding: try JSONEncoder().encode(options), as: UTF8.self)
        try output.write(
            contentsOf: Data(
                ("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{\"configOptions\":\(snapshot)}}\n").utf8))
    }

    func close() { try? output.close() }
}

@main
@MainActor
private struct ComposerRowSettingsRegression {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw RowCheckFailure(message) }
    }

    static func wait(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RowCheckFailure("Timed out: \(message)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func actions(_ app: AppModel, _ session: SessionModel) -> ComposerRowActions {
        ComposerRowModelAdapter(app: app, session: session).actions(attach: {}, context: {}, send: {})
    }

    static func fixture(
        _ connection: ACPConnection, changeAgent: Bool = true, extraOptions: String = "[]", standardOnly: Bool = false
    ) throws -> (
        AppModel, SessionModel, [JSONValue]
    ) {
        let defaults = PreviewUserDefaults()
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(changeAgent, for: .changeAgent)
        let app = AppModel(
            plugins: PluginRegistry(previewing: [BuiltInPlugins.claudeCode]), defaults: defaults,
            catalogURL: nil, experiments: experiments)
        guard let agent = app.plugins.agent(.init(rawValue: "claude-code")) else {
            throw RowCheckFailure("Missing fixture agent")
        }
        let decoder = JSONDecoder()
        let reported =
            try decoder.decode([JSONValue].self, from: Data(GatewayWire.configOptions.utf8))
            + decoder.decode([JSONValue].self, from: Data(extraOptions.utf8))
        let wire =
            standardOnly
            ? reported.filter {
                [.string("model"), .string("thought_level"), .string("mode")].contains($0["category"])
            } : reported
        let options = try decoder.decode([ConfigOption].self, from: JSONEncoder().encode(wire))
        let session = SessionModel(
            agent: agent, id: SessionID("composer-row-\(UUID())"), cwd: URL(filePath: "/fixture"),
            connection: connection, services: app.sessions.services, supportsSteering: false,
            phase: .idle, configOptions: options)
        return (app, session, wire)
    }

    static func modelID(_ app: AppModel, _ session: SessionModel, value: String) throws -> String {
        guard let row = app.composerAgentModels(for: session).first(where: { $0.kind == .model(value) })
        else {
            throw RowCheckFailure("Missing model choice")
        }
        return row.id
    }

    static func apply(_ request: JSONValue, to options: inout [JSONValue]) throws {
        guard case .string(let id) = request["params"]?["configId"],
            case .string(let value) = request["params"]?["value"],
            let index = options.firstIndex(where: { $0["id"] == .string(id) }),
            case .object(var option) = options[index]
        else { throw RowCheckFailure("Unexpected settings request: \(request)") }
        option["currentValue"] = .string(value)
        options[index] = .object(option)
    }

    static func freshModel() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (app, session, initial) = try fixture(agent.connection)
        try require(session.isTranscriptEmpty, "Fixture must have no first message")
        actions(app, session).chooseModel(try modelID(app, session, value: "sonnet"))
        try await wait("same-agent model request before first message") { !agent.received.isEmpty }
        var reply = initial
        try apply(agent.received[0], to: &reply)
        try agent.reply(agent.received[0], options: reply)
        try await wait("model confirmation") {
            ComposerSettings(session.configOptions).model?.value == "sonnet"
        }
        try require(session.modelChange == nil, "Same-agent choice created a handoff")
        try require(session.isTranscriptEmpty, "Model choice created a conversation message")
        print("PASS: fresh connected task changes its model without handoff or first message")
    }

    static func orderedSnapshots() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (app, session, initial) = try fixture(agent.connection)
        actions(app, session).chooseEffort("high")
        try await wait("delayed effort request") { agent.received.count == 1 }
        // Each action comes from a new adapter, as after menu dismissal and state recomputation.
        actions(app, session).chooseMode("ask-first")
        actions(app, session).chooseModel(try modelID(app, session, value: "sonnet"))
        try await Task.sleep(for: .milliseconds(100))
        try require(agent.received.count == 1, "Later requests overlap the held full-snapshot reply")
        var snapshot = initial
        for index in 0..<3 {
            try await wait("queued request \(index)") { agent.received.count > index }
            let request = agent.received[index]
            try apply(request, to: &snapshot)
            try agent.reply(request, options: snapshot)
        }
        try await wait("all settings confirmed") {
            let settings = ComposerSettings(session.configOptions)
            return settings.model?.value == "sonnet" && settings.effort?.value == "high"
                && settings.autonomy?.value == "ask-first"
        }
        let order = agent.received.map { $0["params"]?["configId"] }
        try require(
            order == [.string("effort"), .string("mode"), .string("model")], "Settings lost user order")
        try require(session.modelChange == nil, "Queued same-agent model started a handoff")
        print("PASS: delayed full snapshots preserve effort, mode and model across adapter recreation")
    }

    static func repeatedSelections() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (app, session, initial) = try fixture(agent.connection)
        actions(app, session).chooseEffort("high")
        try await wait("held effort request") { agent.received.count == 1 }
        actions(app, session).chooseEffort("low")
        actions(app, session).chooseMode("ask-first")
        actions(app, session).chooseEffort("high")
        try await Task.sleep(for: .milliseconds(100))
        try require(agent.received.count == 1, "Repeated choices overlap the held reply")
        var snapshot = initial
        for index in 0..<4 {
            try await wait("repeated selection \(index)") { agent.received.count > index }
            let request = agent.received[index]
            try apply(request, to: &snapshot)
            try agent.reply(request, options: snapshot)
        }
        try await wait("repeated selections confirmed") {
            let settings = ComposerSettings(session.configOptions)
            return settings.effort?.value == "high" && settings.autonomy?.value == "ask-first"
        }
        let order = agent.received.map { $0["params"]?["configId"] }
        try require(
            order == [.string("effort"), .string("effort"), .string("mode"), .string("effort")],
            "Repeated settings lost user order")
        let values = agent.received.map { $0["params"]?["value"] }
        try require(
            values == [.string("high"), .string("low"), .string("default"), .string("high")],
            "Repeated selections lost user order: \(values)")
        print("PASS: repeated effort selections survive in-flight and queued replies")
    }

    static func currentAgentWithoutTransitions() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (app, session, initial) = try fixture(agent.connection, changeAgent: false)
        let state = ComposerRowModelAdapter(app: app, session: session).state
        try require(state.agents.count == 1, "Only the current agent may be offered")
        guard let model = state.agents.first?.models.first(where: { $0.title.lowercased().contains("sonnet") }) else {
            throw RowCheckFailure("Current agent model choices disappeared")
        }
        actions(app, session).chooseModel(model.id)
        try await wait("model request with Change Agent off") { agent.received.count == 1 }
        var reply = initial
        try apply(agent.received[0], to: &reply)
        try agent.reply(agent.received[0], options: reply)
        try await wait("model confirmation") { ComposerSettings(session.configOptions).model?.value == "sonnet" }
        actions(app, session).chooseEffort("high")
        try await wait("effort request with Change Agent off") { agent.received.count == 2 }
        try apply(agent.received[1], to: &reply)
        try agent.reply(agent.received[1], options: reply)
        try await wait("effort confirmation") { ComposerSettings(session.configOptions).effort?.value == "high" }
        try require(session.modelChange == nil, "Current model or effort created a handoff")
        print("PASS: Composer field preserves model and effort with Change Agent off")
    }

    static func folderContinuation() async throws {
        for paths in [
            ["native/", "native/Composer/", "native/Composer/ComposerField.swift"],
            ["src/", "src/@scope/", "src/@scope/foo.swift"],
            ["my folder/", "my folder/child folder/", "my folder/child folder/file.swift"],
        ] {
            var document = TextInputDocument("@./")
            var selection = NSRange(location: 3, length: 0)
            for path in paths {
                guard let query = TextInputQuery(document: document, selection: selection),
                    let result = ComposerFieldCompletion.file(path).inserting(in: document, query: query)
                else {
                    throw RowCheckFailure("Folder query ended before \(path)")
                }
                document = result.document
                selection = result.selection
                try require(result.continues == path.hasSuffix("/"), "Wrong completion dismissal")
                if result.continues {
                    try require(
                        TextInputQuery(document: document, selection: selection)?.text == path,
                        "Folder caret must stay inside the editable path")
                }
            }
            try require(document.runs == [.mention(path: paths[2]), .text(" ")], "Final file must be atomic")
        }
        let adjacent = TextInputDocument(runs: [.mention(path: "one.swift"), .text("@two")])
        let selection = NSRange(location: adjacent.displayText.utf16.count, length: 0)
        guard let query = TextInputQuery(document: adjacent, selection: selection),
            let accepted = ComposerFieldCompletion.file("two.swift").inserting(in: adjacent, query: query)
        else { throw RowCheckFailure("A query after an atomic mention was rejected") }
        try require(
            accepted.document.runs == [.mention(path: "one.swift"), .mention(path: "two.swift"), .text(" ")],
            "Completion must preserve the adjacent atomic mention")
        print("PASS: field accepts folders, quoted paths, embedded @ paths and atomic-token boundaries")
    }

    static func cancelQueuedFieldEdit() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (_, session, _) = try fixture(agent.connection)
        session.queue.append("original queued message")
        let queued = session.queuedPrompts
        for phase in [SessionModel.Phase.idle, .prompting] {
            session.phase = phase
            session.editingQueuedPrompt = queued.first?.id
            session.draft = "unsaved change"
            try require(ComposerView(session: session).cancelFieldQueuedEdit(), "Escape must consume queued edit")
            try require(session.editingQueuedPrompt == nil && session.draft.isEmpty, "Queued edit stayed open")
            try require(session.queuedPrompts == queued, "Escape changed queued content")
            try require(session.phase == phase && !session.isStopping, "Escape interrupted the running turn")
        }
        try require(agent.received.isEmpty, "Queued edit cancellation sent an agent request")
        print("PASS: queued field edits cancel without saving or stopping in idle and running tasks")
    }

    static func locationOnlyBeforeStarting() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (app, session, _) = try fixture(agent.connection)
        let project = app.projects.add(URL(filePath: "/fixture", directoryHint: .isDirectory))
        app.quickEntry.project = project.id
        app.composeTask.workspace = .project
        try require(
            ComposerRowModelAdapter(app: app).state.locations.map(\.id) == ["project", "branch"],
            "A new task must offer both locations")
        for phase in [SessionModel.Phase.idle, .prompting, .disconnected] {
            session.phase = phase
            try require(
                ComposerRowModelAdapter(app: app, session: session).state.locations.isEmpty,
                "An existing task must not offer Where in \(phase)")
        }
        app.quickEntry.project = nil
        try require(
            ComposerRowModelAdapter(app: app).state.locations.isEmpty,
            "A new task without a project must not offer Where")
        print("PASS: Where is limited to new tasks with a project, across existing-task phases")
    }

    static func extraAgentSettings() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let (plainApp, plainSession, _) = try fixture(agent.connection, standardOnly: true)
        try require(
            ComposerRowModelAdapter(app: plainApp, session: plainSession).state.agents.allSatisfy {
                $0.settings.isEmpty
            }, "An agent without extras must not gain a settings section")
        let extras = """
            [
                {"id":"style","name":"Response style","type":"select","currentValue":"concise",
                 "options":[{"value":"concise","name":"Concise"},{"value":"detailed","name":"Detailed"}]},
                {"id":"verbosity","name":"Verbosity","category":"model_config","type":"select",
                 "currentValue":"normal","options":[{"value":"normal","name":"Normal"}]},
                {"id":"future","name":"Future control","type":"boolean","currentValue":false},
                {"id":"plan","name":"Plan","category":"collaboration_mode","type":"select",
                 "currentValue":"default","options":[{"value":"default","name":"Default"},{"value":"plan","name":"Plan"}]}
            ]
            """
        let (app, session, initial) = try fixture(agent.connection, extraOptions: extras)
        let state = ComposerRowModelAdapter(app: app, session: session).state
        try require(
            state.agents.first(where: { $0.id == session.agent.id.rawValue })?.settings.map(\.option.id)
                == ["fast", "style", "verbosity"],
            "Extra controls must reuse select settings, without duplicating model, effort, mode or Plan")
        try require(
            state.agents.filter { $0.id != session.agent.id.rawValue }.allSatisfy { $0.settings.isEmpty },
            "Current settings must not appear under other agents")
        actions(app, session).chooseSetting("fast", "on")
        try await wait("extra setting request") { agent.received.count == 1 }
        actions(app, session).chooseSetting("style", "detailed")
        actions(app, session).chooseSetting("fast", "invalid")
        actions(app, session).chooseSetting("missing", "on")
        actions(app, session).chooseSetting("mode", "ask-first")
        var reply = initial
        for index in 0..<2 {
            try await wait("extra setting \(index)") { agent.received.count > index }
            try apply(agent.received[index], to: &reply)
            try agent.reply(agent.received[index], options: reply)
        }
        try await wait("extra settings confirmation") {
            let settings = ComposerSettings(session.configOptions)
            return settings.modelSwitches.first?.value == "on"
                && settings.others.first(where: { $0.option.id == "style" })?.value == "detailed"
        }
        try require(
            agent.received.map { $0["params"]?["configId"] } == [.string("fast"), .string("style")],
            "Extra picks must use option IDs and reject invalid or dedicated-control picks")
        try require(
            session.isTranscriptEmpty && session.modelChange == nil, "Extra settings started a message or handoff")
        print("PASS: agent extras appear only when offered and apply by ID through ordered config requests")
    }

    static func newTaskExtraSettings() async throws {
        let agent = await RowSettingsAgent()
        defer { agent.close() }
        let extras = """
            [
                {"id":"style","name":"Response style","type":"select","currentValue":"concise",
                 "options":[{"value":"concise","name":"Concise"},{"value":"detailed","name":"Detailed"}]},
                {"id":"verbosity","name":"Verbosity","category":"model_config","type":"select",
                 "currentValue":"normal","options":[{"value":"normal","name":"Normal"},{"value":"more","name":"More"}]}
            ]
            """
        let (app, session, initial) = try fixture(agent.connection, extraOptions: extras)
        _ = app.runtimes.sync()
        let compose = app.composeTask
        compose.configuredAgent = session.agent.id
        compose.options = session.configOptions
        compose.defaults = compose.addressedChoices
        let adapter = ComposerRowModelAdapter(app: app)
        let offered = adapter.state.agents.first { $0.id == session.agent.id.rawValue }?.settings ?? []
        try require(offered.map(\.option.id) == ["fast", "style", "verbosity"], "Unsent task omitted agent extras")
        try require(
            adapter.state.agents.filter { $0.id != session.agent.id.rawValue }.allSatisfy { $0.settings.isEmpty },
            "Unsent task showed extras for an unselected agent")
        let picks = adapter.actions(attach: {}, context: {}, send: {})
        picks.chooseSetting("fast", "on")
        picks.chooseSetting("style", "detailed")
        picks.chooseSetting("verbosity", "more")
        let expected = compose.addressedChoices
        try require(
            expected["option:fast"] == "on" && expected["option:style"] == "detailed"
                && expected["option:verbosity"] == "more",
            "Extra choices must survive by ID, including absent and shared categories")
        picks.chooseSetting("fast", "invalid")
        picks.chooseSetting("missing", "on")
        picks.chooseSetting("mode", "ask-first")
        try require(compose.addressedChoices == expected, "An invalid or dedicated setting changed the draft")
        compose.isHeld = true
        picks.chooseSetting("fast", "off")
        try require(compose.addressedChoices == expected, "Held draft accepted a setting change")
        compose.isHeld = false
        compose.stage = .folding
        picks.chooseSetting("style", "concise")
        try require(compose.addressedChoices == expected, "Starting draft accepted a setting change")
        compose.stage = .writing
        try require(agent.received.isEmpty, "Unsent choices contacted an agent")

        let task = StartingTask(
            project: UUID(), agent: session.agent, isAgentPicked: true, workspaceLabel: "Fixture")
        task.configChoices = expected.filter { $0.key.hasPrefix("option:") }
        task.isSendRequested = true
        let applying = Task { await app.applyComposeChoices(of: task, to: session) }
        var reply = initial
        for index in 0..<3 {
            try await wait("new-task extra setting \(index)") { agent.received.count > index }
            try apply(agent.received[index], to: &reply)
            try agent.reply(agent.received[index], options: reply)
        }
        await applying.value
        try require(task.isSendRequested, "Confirmed extra choices blocked the first message")
        try require(
            agent.received.map { $0["params"]?["configId"] }
                == [.string("fast"), .string("style"), .string("verbosity")],
            "New-task extras did not apply by ID before the first message")
        task.configChoices = ["option:removed": "on"]
        await app.applyComposeChoices(of: task, to: session)
        try require(!task.isSendRequested, "Removed extra setting allowed the first message to send")
        compose.options = compose.options.filter { ["model", "thought_level", "mode"].contains($0.category ?? "") }
        try require(
            ComposerRowModelAdapter(app: app).state.agents.allSatisfy { $0.settings.isEmpty },
            "An unsent task without extras gained a settings section")
        print("PASS: unsent task offers extras, keeps local picks and applies them by ID before sending")
    }

    static func main() async {
        let domain = ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        var failures = 0
        for check in [
            freshModel, orderedSnapshots, repeatedSelections, currentAgentWithoutTransitions, folderContinuation,
            cancelQueuedFieldEdit, locationOnlyBeforeStarting, extraAgentSettings, newTaskExtraSettings,
        ] {
            do { try await check() } catch {
                failures += 1
                print("FAIL: \(error)")
            }
        }
        if failures > 0 { exit(1) }
    }
}
