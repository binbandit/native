#if os(macOS)
import Foundation
import Synchronization

/// Runs commands on this Mac.
public struct LocalCommandRunner: CommandRunner {
    public init() {}

    public func run(_ command: Command) async throws -> CommandResult {
        try Task.checkCancellation()
        guard let executable = Self.resolve(command.executable, path: command.environment["PATH"]) else {
            throw CommandError.notFound(command.executable)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = command.arguments
        process.environment = command.environment
        if let directory = command.directory {
            process.currentDirectoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        }
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        // Drain both pipes as data arrives: a command that fills one pipe's buffer while nobody reads
        // it would block forever.
        let collected = Collected()
        output.fileHandleForReading.readabilityHandler = { collected.append($0.availableData, to: \.output) }
        error.fileHandleForReading.readabilityHandler = { collected.append($0.availableData, to: \.error) }

        let lifecycle = Lifecycle(process)
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try lifecycle.launch()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                if let stdin = command.standardInput {
                    try? input.fileHandleForWriting.write(contentsOf: stdin)
                }
                try? input.fileHandleForWriting.close()
                if let timeout = command.timeout {
                    Task {
                        try? await Task.sleep(for: timeout)
                        lifecycle.stop(.timedOut)
                    }
                }
            }
        } onCancel: {
            lifecycle.stop(.cancelled)
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        // Whatever arrived after the last readability callback.
        collected.append(output.fileHandleForReading.readDataToEndOfFile(), to: \.output)
        collected.append(error.fileHandleForReading.readDataToEndOfFile(), to: \.error)

        switch lifecycle.stopReason {
        case .cancelled: throw CancellationError()
        case .timedOut: throw CommandError.timedOut(command.executable, after: command.timeout ?? .zero)
        case nil: break
        }
        let (standardOutput, standardError) = collected.snapshot
        return CommandResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError)
    }

    private static func resolve(_ executable: String, path: String?) -> URL? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? URL(filePath: executable) : nil
        }
        return (path ?? "").split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: executable) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }
}

/// Serializes launching against stopping. Cancellation can arrive before the process has launched,
/// and `Process.terminate()` raises an Objective-C exception for a process that never ran.
private final class Lifecycle: @unchecked Sendable {
    enum StopReason: Sendable {
        case cancelled
        case timedOut
    }

    private struct State {
        var launched = false
        var stopReason: StopReason?
    }

    // `Process` isn't Sendable; every access goes through `state`'s lock.
    private let process: Process
    private let state = Mutex(State())

    init(_ process: Process) {
        self.process = process
    }

    var stopReason: StopReason? { state.withLock { $0.stopReason } }

    /// Launches the process, unless it was cancelled first.
    func launch() throws {
        try state.withLock { state in
            if state.stopReason == .cancelled { throw CancellationError() }
            try process.run()
            state.launched = true
        }
    }

    /// Records why the command stopped early and terminates it if it's still running. The first reason
    /// wins; stopping a process that already exited does nothing.
    func stop(_ reason: StopReason) {
        state.withLock { state in
            guard state.stopReason == nil else { return }
            if state.launched {
                guard process.isRunning else { return }
                process.terminate()
            }
            state.stopReason = reason
        }
    }
}

private final class Collected: Sendable {
    struct Buffers {
        var output = Data()
        var error = Data()
    }

    private let buffers = Mutex(Buffers())

    func append(_ data: Data, to stream: WritableKeyPath<Buffers, Data> & Sendable) {
        guard !data.isEmpty else { return }
        buffers.withLock { $0[keyPath: stream].append(data) }
    }

    var snapshot: (Data, Data) {
        buffers.withLock { ($0.output, $0.error) }
    }
}
#endif
