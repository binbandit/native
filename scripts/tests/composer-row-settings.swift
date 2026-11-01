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
        _ connection: ACPConnection, changeAgent: Bool = true
    ) throws -> (
        AppModel, SessionModel, [JSONValue]
    ) {
        let defaults = PreviewUserDefaults()
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(changeAgent, for: .changeAgent)
        experiments.set(true, for: .composerV3)
        let app = AppModel(
            plugins: PluginRegistry(previewing: [BuiltInPlugins.claudeCode]), defaults: defaults,
            catalogURL: nil, experiments: experiments)
        guard let agent = app.plugins.agent(.init(rawValue: "claude-code")) else {
            throw RowCheckFailure("Missing fixture agent")
        }
        let options = try GatewayWire.options()
        let session = SessionModel(
            agent: agent, id: SessionID("composer-row-\(UUID())"), cwd: URL(filePath: "/fixture"),
            connection: connection, services: app.sessions.services, supportsSteering: false,
            phase: .idle, configOptions: options)
        return (app, session, try JSONDecoder().decode([JSONValue].self, from: Data(GatewayWire.configOptions.utf8)))
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
        print("PASS: assembled field accepts repeated folders and quoted folder paths")
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

    static func main() async {
        let domain = ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        var failures = 0
        for check in [
            freshModel, orderedSnapshots, repeatedSelections, currentAgentWithoutTransitions, folderContinuation,
            cancelQueuedFieldEdit,
        ] {
            do { try await check() } catch {
                failures += 1
                print("FAIL: \(error)")
            }
        }
        if failures > 0 { exit(1) }
    }
}
