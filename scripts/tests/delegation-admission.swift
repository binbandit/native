import ACP
import Foundation
import NativeOrchestration

@testable import Native

@main
@MainActor
struct DelegationAdmissionCheck {
    struct Failure: Error { let message: String }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(message: "Fixture timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func main() async {
        do { try await run() } catch { print("FAIL: \(error)"); exit(1) }
    }

    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "delegation-admission-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PluginManifest(
            id: "delegation-fixture", name: "Delegation fixture",
            agents: [
                AgentManifest(
                    id: "fixture", name: "Fixture", command: "/usr/bin/python3",
                    args: [CommandLine.arguments[1], root.path])
            ])
        let defaults = PreviewUserDefaults()
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil)
        defer { app.stopAgents() }
        _ = await app.checkForAgents()
        _ = await app.ensureRunning(.init(rawValue: "fixture"))
        let raw =
            #"[{"id":"mode","name":"Permissions","category":"mode","type":"select","currentValue":"default","options":[{"value":"default","name":"Default"}]}]"#
        let options = try JSONDecoder().decode([ConfigOption].self, from: Data(raw.utf8))
        guard
            let parent = SessionModel.preview(
                in: app, agent: "fixture", cwd: root.path, phase: .prompting, configOptions: options)
        else { throw Failure(message: "No parent fixture") }
        let runtime = AppTaskRuntime(defaults: defaults)
        runtime.model = app
        func request(model: String? = nil) -> TaskRequest {
            TaskRequest(
                id: UUID().uuidString, agent: TaskAgent(id: "fixture", name: "Fixture"),
                parent: TaskSessionRef(parent.key), parentAgentName: "Fixture", title: "Admission check",
                text: "Check admission", prompt: "Check admission", options: .init(model: model))
        }
        func calls() throws -> [[String: Any]] {
            let url = root.appending(path: "calls.jsonl")
            return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] ?? [:]
            }
        }
        switch CommandLine.arguments[2] {
        case "cleanup":
            for _ in 0..<3 {
                do {
                    _ = try await runtime.startTask(request(model: "missing"))
                    throw Failure(message: "Invalid model was admitted")
                } catch is TaskLaunchValidation.Refusal {}
            }
            try require(app.sessions.loadedSessions.count == 1, "Refusal leaked registered candidates")
            try require(parent.children.isEmpty, "Refusal leaked child ownership")
            try require(runtime.tasks().isEmpty, "Refusal created a task receipt")
            let saved =
                try defaults.data(forKey: "taskSessions").map {
                    try JSONDecoder().decode([TaskSessionRecords.Record].self, from: $0)
                } ?? []
            try require(saved.isEmpty, "Refusal left persisted task sessions")
            let candidates = try calls().filter { $0["method"] as? String == "session/new" }
            try require(candidates.count == 3, "Fixture did not create three candidates")
            // All candidates must be closed through the agent's advertised session close API.
            try await wait { (try? calls().filter { $0["method"] as? String == "session/close" }.count) == 3 }
        case "resumed":
            parent.lastStopReason = .cancelled
            _ = try await runtime.startTask(request())
            try require(runtime.tasks().count == 1, "A resumed parent could not delegate")
        case "stop":
            let pending = Task { try await runtime.startTask(request(model: "beta")) }
            try await wait { FileManager.default.fileExists(atPath: root.appending(path: "preparing").path) }
            await parent.cancel()
            parent.lastStopReason = .cancelled
            parent.turnDidEnd()
            parent.phase = .prompting
            parent.lastStopReason = .endTurn
            try Data().write(to: root.appending(path: "release"))
            do {
                _ = try await pending.value
                throw Failure(message: "Stop followed by resume admitted stale delegation")
            } catch is TaskLaunchValidation.Refusal {}
            try require(
                parent.children.isEmpty && app.sessions.loadedSessions.count == 1,
                "Stopped admission leaked its candidate")
            try require(
                !calls().contains { $0["method"] as? String == "session/prompt" },
                "Stopped admission prompted a child")
        default: throw Failure(message: "Unknown scenario")
        }
        print("PASS: delegated admission \(CommandLine.arguments[2])")
    }
}
