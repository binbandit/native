import Foundation
import Synchronization
import Testing

@testable import ScriptRuntime

/// A runtime played by the test: it answers what the session sends with frames the test chooses.
final class FakeRuntime: ScriptTransport {
    let frames: AsyncThrowingStream<ScriptOutboundFrame, any Error>
    private let continuation: AsyncThrowingStream<ScriptOutboundFrame, any Error>.Continuation
    private let react: @Sendable (ScriptInboundFrame, FakeRuntime) -> Void
    let received = Mutex<[ScriptInboundFrame]>([])
    let terminated = Mutex(false)

    init(react: @escaping @Sendable (ScriptInboundFrame, FakeRuntime) -> Void) {
        (frames, continuation) = AsyncThrowingStream.makeStream()
        self.react = react
        continuation.yield(.ready(protocolVersion: scriptProtocolVersion))
    }

    func emit(_ frame: ScriptOutboundFrame) { continuation.yield(frame) }
    func end(throwing error: (any Error)? = nil) { continuation.finish(throwing: error) }

    func send(_ frame: ScriptInboundFrame) throws {
        received.withLock { $0.append(frame) }
        react(frame, self)
    }

    func terminate() {
        terminated.withLock { $0 = true }
        continuation.finish()
    }
}

private func run(
    bindings: [ScriptBinding] = [], limits: ScriptLimits = .standard, runtime: FakeRuntime
) async throws -> ScriptRunResult {
    try await ScriptSession.run(code: "", bindings: bindings, inputs: [:], limits: limits, transport: runtime)
}

private let tasks = [
    ScriptBinding(path: ["tasks", "get"]) { input in
        guard input["task_id"] != "missing" else { throw ScriptToolError("There's no task \"missing\"") }
        return ["task_id": input["task_id"] ?? nil, "status": "idle"]
    }
]

@Suite struct ScriptSessionTests {
    @Test func answersToolCallsAndCollectsOutput() async throws {
        let runtime = FakeRuntime { frame, runtime in
            switch frame {
            case .evaluate(_, let bindings, _):
                #expect(bindings.map(\.toolName) == ["tasks.get"])
                runtime.emit(.text("first ", end: false))
                runtime.emit(.text("line", end: true))
                runtime.emit(.toolCall(id: 1, toolName: "tasks.get", input: ["task_id": "t1"]))
                runtime.emit(.toolCall(id: 2, toolName: "tasks.get", input: ["task_id": "missing"]))
            case .toolResult(let id, let isError, let content):
                if id == 1 { #expect(!isError && content["status"] == "idle") }
                if id == 2 {
                    #expect(isError && content == "There's no task \"missing\"")
                    runtime.emit(.result)
                }
            }
        }
        let result = try await run(bindings: tasks, runtime: runtime)
        #expect(result.succeeded)
        #expect(result.output == ["first line"])
        #expect(result.toolCalls.map(\.isError) == [false, true])
        #expect(result.toolCalls.first?.path == ["tasks", "get"])
        #expect(runtime.terminated.withLock { $0 })
    }

    @Test func passesTheScriptsFailureThrough() async throws {
        let failure = ScriptFailure(kind: .exception, message: "TypeError: boom", line: 3, column: 9)
        let runtime = FakeRuntime { frame, runtime in
            if case .evaluate = frame { runtime.emit(.error(failure)) }
        }
        let result = try await run(runtime: runtime)
        #expect(result.failure == failure)
        #expect(result.report == "Script failed at line 3, column 9: TypeError: boom")
    }

    @Test func aCallToAnUnboundToolStopsTheRun() async throws {
        let runtime = FakeRuntime { frame, runtime in
            if case .evaluate = frame { runtime.emit(.toolCall(id: 1, toolName: "fs.read", input: [:])) }
        }
        let result = try await run(bindings: tasks, runtime: runtime)
        #expect(result.failure?.kind == .runtime)
        #expect(result.toolCalls.isEmpty)
    }

    @Test func limitsTheNumberOfToolCalls() async throws {
        let runtime = FakeRuntime { frame, runtime in
            guard case .evaluate = frame else { return }
            for id in 1...3 { runtime.emit(.toolCall(id: UInt32(id), toolName: "tasks.get", input: ["task_id": "t"])) }
        }
        let result = try await run(bindings: tasks, limits: ScriptLimits(toolCalls: 2), runtime: runtime)
        #expect(result.failure?.kind == .toolCallLimit)
    }

    @Test func refusesOversizedToolResults() async throws {
        let big = ScriptBinding(path: ["big"]) { _ in .string(String(repeating: "x", count: 100)) }
        let runtime = FakeRuntime { frame, runtime in
            switch frame {
            case .evaluate: runtime.emit(.toolCall(id: 1, toolName: "big", input: [:]))
            case .toolResult(_, let isError, let content):
                #expect(isError && content.stringValue?.contains("Ask for less") == true)
                runtime.emit(.result)
            }
        }
        _ = try await run(bindings: [big], limits: ScriptLimits(toolResultBytes: 50), runtime: runtime)
    }

    @Test func stopsAScriptThatRunsOutOfTime() async throws {
        let runtime = FakeRuntime { _, _ in }
        let result = try await run(limits: ScriptLimits(time: .milliseconds(100)), runtime: runtime)
        #expect(result.failure?.kind == .timedOut)
        #expect(runtime.terminated.withLock { $0 })
    }

    @Test func reportsARuntimeThatEndsWithoutFinishing() async throws {
        let runtime = FakeRuntime { frame, runtime in
            if case .evaluate = frame { runtime.end(throwing: ScriptProcessTransport.Crashed(signal: 11)) }
        }
        let result = try await run(runtime: runtime)
        #expect(result.failure == ScriptFailure(kind: .runtime, message: "The script runtime crashed (signal 11)"))
    }

    @Test func refusesARuntimeOnAnotherProtocolVersion() async throws {
        let result = try await ScriptSession.run(
            code: "", bindings: [], inputs: [:], limits: .standard, transport: StaleRuntime())
        #expect(result.failure?.kind == .runtime)
        #expect(result.failure?.message.contains("protocol 1") == true)
    }

    @Test func cancellationStopsTheRuntime() async throws {
        let runtime = FakeRuntime { _, _ in }
        let run = Task {
            try await ScriptSession.run(code: "", bindings: [], inputs: [:], limits: .standard, transport: runtime)
        }
        try await Task.sleep(for: .milliseconds(50))
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(runtime.terminated.withLock { $0 })
    }

    @Test func rejectsBindingsThatCollide() {
        let tool = ScriptBinding(path: ["a"]) { _ in nil }
        let nested = ScriptBinding(path: ["a", "b"]) { _ in nil }
        let reserved = ScriptBinding(path: ["constructor"]) { _ in nil }
        #expect(throws: ScriptBindingError.self) { try ScriptSession.index([tool, tool]) }
        #expect(throws: ScriptBindingError.self) { try ScriptSession.index([tool, nested]) }
        #expect(throws: ScriptBindingError.self) { try ScriptSession.index([reserved]) }
    }
}

/// A runtime from an older build that announces protocol 1 and nothing else.
private final class StaleRuntime: ScriptTransport {
    let frames: AsyncThrowingStream<ScriptOutboundFrame, any Error>

    init() {
        let (frames, continuation) = AsyncThrowingStream.makeStream(of: ScriptOutboundFrame.self)
        continuation.yield(.ready(protocolVersion: 1))
        self.frames = frames
    }

    func send(_ frame: ScriptInboundFrame) throws {}
    func terminate() {}
}
