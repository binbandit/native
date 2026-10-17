#if os(macOS)
import Foundation
import Testing

@testable import ScriptRuntime

/// The signed runtime `scripts/build-script-runtime.sh` builds, or the one `NATIVE_SCRIPT_RUNTIME`
/// names. These tests skip when it hasn't been built.
private let helper: URL = {
    if let path = ProcessInfo.processInfo.environment["NATIVE_SCRIPT_RUNTIME"] {
        return URL(filePath: path)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Caches/Native/ScriptRuntime/native-script-runtime")
}()

private let isBuilt = FileManager.default.isExecutableFile(atPath: helper.path(percentEncoded: false))

@Suite(.enabled(if: isBuilt, "Build the runtime with scripts/build-script-runtime.sh"))
struct ScriptRunnerTests {
    let runner: ScriptRunner
    let tasks: [ScriptBinding]

    init() throws {
        runner = try ScriptRunner(helper: helper)
        let snapshots: [String: ScriptJSON] = [
            "t1": ["task_id": "t1", "agent": "codex", "status": "idle", "reply": "LGTM"],
            "t2": ["task_id": "t2", "agent": "claude-code", "status": "running"],
        ]
        tasks = [
            ScriptBinding(path: ["list_tasks"]) { _ in
                ["tasks": .array(snapshots.keys.sorted().map { ["id": .string($0)] })]
            },
            ScriptBinding(path: ["get_task"]) { input in
                guard let id = input["task_id"]?.stringValue, let snapshot = snapshots[id] else {
                    throw ScriptToolError("There's no task \"\(input["task_id"]?.stringValue ?? "")\"")
                }
                return snapshot
            },
        ]
    }

    @Test func callsTwoToolsAndPrintsASummary() async throws {
        let result = try await runner.run(
            """
            const { tasks } = await tools.list_tasks();
            const details = await Promise.all(tasks.map((task) => tools.get_task({ task_id: task.id })));
            const done = details.filter((task) => task.status === "idle");
            text(`${done.length} of ${details.length} tasks are done:`, done.map((task) => `${task.task_id} (${task.agent}): ${task.reply}`).join("; "));
            """, bindings: tasks)
        #expect(result.failure == nil)
        #expect(result.text == "1 of 2 tasks are done: t1 (codex): LGTM")
        #expect(result.toolCalls.map(\.path) == [["list_tasks"], ["get_task"], ["get_task"]])
    }

    @Test func failedToolCallsRejectWhereTheyWereMade() async throws {
        let result = try await runner.run("text('looking');\nawait tools.get_task({ task_id: 'nope' });", bindings: tasks)
        #expect(result.output == ["looking"])
        #expect(result.failure?.kind == .exception)
        #expect(result.failure?.line == 2)
        #expect(result.failure?.message.contains("tools.get_task failed: There's no task \"nope\"") == true)
        #expect(result.toolCalls.map(\.isError) == [true])
    }

    @Test func reportsSyntaxErrorsWithTheirPosition() async throws {
        let result = try await runner.run("const a = 1;\nconst b = ;")
        #expect(result.failure?.kind == .syntax)
        #expect(result.failure?.line == 2)
        #expect(result.failure?.column == 11)
    }

    @Test func scriptsCannotEscape() async throws {
        let result = try await runner.run(
            """
            const attempts = {
              require: () => require("child_process").execSync("id"),
              process: () => process.env.HOME,
              fetch: () => fetch("https://example.com"),
              files: () => Deno.readTextFileSync("/etc/passwd"),
              wasm: () => new WebAssembly.Module(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])),
              host: () => __native_host('{"op":"metadata"}'),
            };
            for (const [name, attempt] of Object.entries(attempts)) {
              try { attempt(); text(`${name}: escaped`) } catch (error) { text(`${name}: ${error.name}`) }
            }
            try { await import("node:fs"); text("import: escaped") } catch (error) { text(`import: ${error.name}`) }
            """)
        #expect(result.failure == nil)
        #expect(!result.text.contains("escaped"), "\(result.text)")
        #expect(result.output.count == 7)

        let imported = try await runner.run("import { readFileSync } from 'node:fs';\ntext(readFileSync('/etc/passwd'))")
        #expect(imported.failure?.kind == .syntax)
    }

    @Test func theOperatingSystemSandboxDeniesFilesAndNetwork() throws {
        let secret = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/native-script-runtime-probe-\(UUID().uuidString).txt")
        try Data("secret".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }

        let probe = Process()
        probe.executableURL = helper
        probe.arguments = ["--probe-sandbox", secret.path(percentEncoded: false)]
        let output = Pipe()
        probe.standardOutput = output
        try probe.run()
        probe.waitUntilExit()
        let report = try JSONDecoder().decode(ScriptJSON.self, from: output.fileHandleForReading.readDataToEndOfFile())
        #expect(report == ["fileRead": "denied", "network": "denied"])
    }

    @Test func refusesAnUnsandboxedRuntime() throws {
        let unsigned = FileManager.default.temporaryDirectory.appending(path: "native-script-runtime-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: helper, to: unsigned)
        defer { try? FileManager.default.removeItem(at: unsigned) }
        let strip = Process()
        strip.executableURL = URL(filePath: "/usr/bin/codesign")
        strip.arguments = ["--force", "--sign", "-", unsigned.path(percentEncoded: false)]
        try strip.run()
        strip.waitUntilExit()
        #expect(throws: ScriptRunnerError.notSandboxed(unsigned)) { try ScriptRunner(helper: unsigned) }
    }

    @Test func stopsAScriptThatRunsTooLong() async throws {
        let started = ContinuousClock.now
        let result = try await runner.run("text('spinning'); while (true) {}", limits: ScriptLimits(time: .milliseconds(500)))
        #expect(result.failure?.kind == .timedOut)
        #expect(result.output == ["spinning"])
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func limitsMemory() async throws {
        let result = try await runner.run(
            "const hoard = []; while (true) hoard.push('x'.repeat(4096) + hoard.length);",
            limits: ScriptLimits(heapMiB: 32))
        #expect(result.failure?.kind == .memory)
    }

    @Test func cancellationStopsTheScript() async throws {
        let runner = self.runner
        let run = Task { try await runner.run("while (true) {}") }
        try await Task.sleep(for: .milliseconds(300))
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
    }
}
#endif
