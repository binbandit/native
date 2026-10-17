import Foundation
import Synchronization

/// A started runtime as the session sees it: frames out of it, frames into it.
protocol ScriptTransport: Sendable {
    /// Ends when the runtime does; throws if it sent something unreadable or died by a signal.
    var frames: AsyncThrowingStream<ScriptOutboundFrame, any Error> { get }
    func send(_ frame: ScriptInboundFrame) throws
    /// Stops the runtime at once; `frames` then ends.
    func terminate()
}

/// Runs one script over a transport: sends it, answers its tool calls, collects its output, and
/// enforces the host's side of the limits. Independent of how the runtime is started, so tests can
/// drive it with a scripted transport.
enum ScriptSession {
    /// More than the runtime ever sends (5 MiB), so only a runtime that's lost control trips it.
    static let maxOutputBytes = 6 << 20

    static func run(
        code: String,
        bindings: [ScriptBinding],
        inputs: [String: String],
        limits: ScriptLimits,
        transport: some ScriptTransport
    ) async throws -> ScriptRunResult {
        let byName = try index(bindings)
        let started = ContinuousClock.now
        let shared = SharedState()
        var output: [String] = []
        var pending = ""
        var outputBytes = 0
        var finished = false
        var failure: ScriptFailure?

        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    guard (try? await Task.sleep(for: limits.time)) != nil else { return }
                    shared.timedOut.withLock { $0 = true }
                    transport.terminate()
                }
                do {
                    frames: for try await frame in transport.frames {
                        switch frame {
                        case .ready(let version) where version == scriptProtocolVersion:
                            let wire = bindings.map { ScriptInboundFrame.Binding(path: $0.path, toolName: $0.toolName) }
                            try transport.send(.evaluate(code: code, bindings: wire, inputs: inputs))
                        case .ready(let version):
                            failure = runtimeFailure(
                                "The script runtime speaks protocol \(version), not \(scriptProtocolVersion)")
                            break frames
                        case .evaluationStarted:
                            break
                        case .text(let piece, let end):
                            outputBytes += piece.utf8.count
                            guard outputBytes <= maxOutputBytes else {
                                failure = runtimeFailure("The script runtime sent more output than its limit")
                                break frames
                            }
                            pending += piece
                            if end {
                                output.append(pending)
                                pending = ""
                            }
                        case .toolCall(let id, let toolName, let input):
                            guard let binding = byName[toolName] else {
                                failure = runtimeFailure(
                                    "The script runtime called a tool that isn't bound: \(toolName)")
                                break frames
                            }
                            let index = shared.calls.withLock { calls in
                                calls.append(
                                    ScriptToolCall(path: binding.path, input: input, isError: false, duration: .zero))
                                return calls.count - 1
                            }
                            guard index < limits.toolCalls else {
                                failure = ScriptFailure(
                                    kind: .toolCallLimit,
                                    message: "The script made more than \(limits.toolCalls) tool calls")
                                break frames
                            }
                            group.addTask {
                                let (isError, content, duration) = await invoke(binding, input: input, limits: limits)
                                shared.calls.withLock { calls in
                                    calls[index].isError = isError
                                    calls[index].duration = duration
                                }
                                // The runtime may have finished meanwhile; then nobody is waiting.
                                try? transport.send(.toolResult(id: id, isError: isError, content: content))
                            }
                        case .result:
                            finished = true
                            break frames
                        case .error(let error):
                            failure = error
                            break frames
                        }
                    }
                } catch {
                    failure = runtimeFailure((error as? LocalizedError)?.errorDescription ?? "\(error)")
                }
                transport.terminate()
                group.cancelAll()
            }
        } onCancel: {
            transport.terminate()
        }

        try Task.checkCancellation()
        if shared.timedOut.withLock({ $0 }) {
            failure = ScriptFailure(kind: .timedOut, message: "The script ran past its \(limits.time) limit")
        } else if !finished && failure == nil {
            failure = runtimeFailure("The script runtime stopped before the script finished")
        }
        return ScriptRunResult(
            output: output, toolCalls: shared.calls.withLock { $0 }, failure: failure,
            duration: ContinuousClock.now - started)
    }

    /// Bindings by the tool name the runtime reports, after checking their paths make sense.
    static func index(_ bindings: [ScriptBinding]) throws -> [String: ScriptBinding] {
        let reserved: Set<String> = ["__proto__", "constructor", "prototype"]
        var byName: [String: ScriptBinding] = [:]
        for binding in bindings {
            guard !binding.path.isEmpty, binding.path.allSatisfy({ !$0.isEmpty && !reserved.contains($0) }) else {
                throw ScriptBindingError("\(binding.label) isn't a usable tool path")
            }
            guard byName.updateValue(binding, forKey: binding.toolName) == nil else {
                throw ScriptBindingError("Two tools are bound at \(binding.label)")
            }
        }
        for binding in bindings where binding.path.count > 1 {
            for depth in 1..<binding.path.count where byName[binding.path[..<depth].joined(separator: ".")] != nil {
                throw ScriptBindingError("\(binding.label) sits inside another tool's path")
            }
        }
        return byName
    }

    /// What the session's child tasks write to.
    private final class SharedState: Sendable {
        let calls = Mutex<[ScriptToolCall]>([])
        let timedOut = Mutex(false)
    }

    private static func invoke(
        _ binding: ScriptBinding, input: ScriptJSON, limits: ScriptLimits
    ) async -> (isError: Bool, content: ScriptJSON, duration: Duration) {
        let started = ContinuousClock.now
        do {
            let content = try await binding.tool.call(input)
            let size = content.jsonText.utf8.count
            guard size <= limits.toolResultBytes else {
                let message =
                    "The result is \(size.formatted(.byteCount(style: .memory))), over the "
                    + "\(limits.toolResultBytes.formatted(.byteCount(style: .memory))) a script can receive. Ask for less."
                return (true, .string(message), ContinuousClock.now - started)
            }
            return (false, content, ContinuousClock.now - started)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return (true, .string(message), ContinuousClock.now - started)
        }
    }

    private static func runtimeFailure(_ message: String) -> ScriptFailure {
        ScriptFailure(kind: .runtime, message: message)
    }
}

/// Bindings that can't all be exposed to one script.
public struct ScriptBindingError: LocalizedError, Sendable {
    public var message: String

    init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
