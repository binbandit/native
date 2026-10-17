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
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Both pipes are drained from the start, so a command that fills one pipe's buffer can't block,
        // and each read ends only at EOF, so no output is lost or reordered.
        async let standardOutput = Self.readToEnd(outputPipe.fileHandleForReading)
        async let standardError = Self.readToEnd(errorPipe.fileHandleForReading)

        let lifecycle = Lifecycle(process)
        let exitCode: Int32
        do {
            exitCode = try await withTaskCancellationHandler {
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
                        try? inputPipe.fileHandleForWriting.write(contentsOf: stdin)
                    }
                    try? inputPipe.fileHandleForWriting.close()
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
        } catch {
            // Nothing launched, so nothing will close the write ends: close them to end the reads.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            _ = await (standardOutput, standardError)
            throw error
        }
        let result = CommandResult(
            exitCode: exitCode,
            standardOutput: await standardOutput,
            standardError: await standardError
        )

        switch lifecycle.stopReason {
        case .cancelled: throw CancellationError()
        case .timedOut: throw CommandError.timedOut(command.executable, after: command.timeout ?? .zero)
        case nil: return result
        }
    }

    /// Reads a pipe until every writer has closed it.
    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "Exec.LocalCommandRunner.read")
            let buffer = Mutex(Data())
            let channel = DispatchIO(type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue) { _ in }
            channel.setLimit(lowWater: 1)
            channel.read(offset: 0, length: .max, queue: queue) { done, data, _ in
                if let data, !data.isEmpty {
                    buffer.withLock { $0.append(contentsOf: data) }
                }
                guard done else { return }
                channel.close()
                // The handle owns the descriptor; keep it open until the read is done.
                withExtendedLifetime(handle) {}
                continuation.resume(returning: buffer.withLock { $0 })
            }
        }
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
#endif
