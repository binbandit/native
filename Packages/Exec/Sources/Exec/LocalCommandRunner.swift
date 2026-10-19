#if os(macOS)
import Foundation
import Synchronization

/// Runs commands on this Mac.
public struct LocalCommandRunner: CommandRunner {
    /// How long a command that ignores being asked to stop gets before it's killed.
    static let stopGracePeriod = Duration.seconds(3)
    /// How long output already written by a command that exited gets to arrive, when the command's
    /// output ends at exit.
    static let exitDrainPeriod = Duration.milliseconds(100)

    public init() {}

    public func run(_ command: Command) async throws -> CommandResult {
        try await run(command, streaming: nil)
    }

    public func run(
        _ command: Command, onOutput: @escaping @Sendable (CommandOutput) -> Void
    ) async throws -> CommandResult {
        try await run(command, streaming: onOutput)
    }

    private func run(
        _ command: Command, streaming onOutput: (@Sendable (CommandOutput) -> Void)?
    ) async throws -> CommandResult {
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

        // Our ends of the pipes move to descriptors that only their channels close (see `PipeEnd`).
        let outputEnd = try PipeEnd(outputPipe.fileHandleForReading)
        let errorEnd = try PipeEnd(errorPipe.fileHandleForReading)
        let inputEnd = try PipeEnd(inputPipe.fileHandleForWriting)

        // Both pipes are drained from the start, so a command that fills one pipe's buffer can't block,
        // and each read ends only at EOF, so no output is lost or reordered.
        let standardOutput = PipeReader(outputEnd) {
            onOutput?(CommandOutput(stream: .standardOutput, data: $0))
        }
        let standardError = PipeReader(errorEnd) {
            onOutput?(CommandOutput(stream: .standardError, data: $0))
        }
        inputEnd.write(command.standardInput)

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
            // Nothing launched, so nothing will close the command's ends of the pipes: close them to end
            // the reads and the write.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            try? inputPipe.fileHandleForReading.close()
            _ = await (standardOutput.untilClosed(), standardError.untilClosed())
            throw error
        }
        let output: Data
        let errors: Data
        if command.outputEndsAtExit {
            // What it wrote before exiting is in the pipes already; what it left running keeps writing.
            try? await Task.sleep(for: Self.exitDrainPeriod)
            output = standardOutput.detach()
            errors = standardError.detach()
        } else {
            (output, errors) = await (standardOutput.untilClosed(), standardError.untilClosed())
        }
        let result = CommandResult(exitCode: exitCode, standardOutput: output, standardError: errors)

        switch lifecycle.stopReason {
        case .cancelled: throw CancellationError()
        case .timedOut: throw CommandError.timedOut(command.executable, after: command.timeout ?? .zero)
        case nil: return result
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

/// Reads a pipe until every writer has closed it, handing over each piece as it arrives.
private final class PipeReader: Sendable {
    private struct State {
        var data = Data()
        var isDetached = false
        var isClosed = false
        var waiter: CheckedContinuation<Data, Never>?
    }

    private let state = Mutex(State())

    init(_ end: consuming PipeEnd, onData: @escaping @Sendable (Data) -> Void) {
        let queue = DispatchQueue(label: "Exec.LocalCommandRunner.read")
        let channel = end.makeChannel(queue: queue)
        channel.setLimit(lowWater: 1)
        // The handler keeps the reader alive until EOF, even once nobody waits for it any more.
        channel.read(offset: 0, length: .max, queue: queue) { [self] done, data, _ in
            if let data, !data.isEmpty {
                let chunk = Data(data)
                let isKept = state.withLock { state in
                    if !state.isDetached { state.data.append(chunk) }
                    return !state.isDetached
                }
                if isKept { onData(chunk) }
            }
            guard done else { return }
            channel.close()
            let (waiter, data) = state.withLock { state in
                state.isClosed = true
                defer { state.waiter = nil }
                return (state.waiter, state.data)
            }
            waiter?.resume(returning: data)
        }
    }

    /// Everything read, once every writer has closed the pipe.
    func untilClosed() async -> Data {
        await withCheckedContinuation { continuation in
            let data: Data? = state.withLock { state in
                guard state.isClosed else {
                    state.waiter = continuation
                    return nil
                }
                return state.data
            }
            if let data { continuation.resume(returning: data) }
        }
    }

    /// What's arrived so far. Reading goes on until the pipe closes, dropping what comes after.
    func detach() -> Data {
        state.withLock { state in
            state.isDetached = true
            return state.data
        }
    }
}

/// Our end of one of the command's pipes, as a descriptor of its own for exactly one dispatch channel.
///
/// libdispatch watches a channel's descriptor until just before the channel's cleanup handler runs.
/// Closed any earlier, the watch vanishes and libdispatch traps ("Unexpected EV_VANISHED"), or, once
/// the number is reused, acts on someone else's file. A pipe's `FileHandle` closes its descriptor
/// whenever the handle is released, so the channel gets a copy that only its cleanup handler closes,
/// and the handle is closed right away. The copy is then this process's only descriptor for the pipe
/// end, so end of file still arrives when it should, in both directions.
private struct PipeEnd: ~Copyable {
    private let descriptor: Int32

    init(_ handle: FileHandle) throws {
        // Close-on-exec, so nothing else this process starts can inherit the pipe and hold it open.
        let descriptor = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        let error = errno
        try? handle.close()
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EMFILE) }
        // Writing to a command that exited without reading its input fails, rather than raising
        // SIGPIPE, which ends the whole process unless it ignores the signal.
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        self.descriptor = descriptor
    }

    /// For an end that never got a channel: setup failed, or there was no input to write.
    deinit {
        close(descriptor)
    }

    /// A stream channel that owns the descriptor, and is the only thing that closes it.
    consuming func makeChannel(queue: DispatchQueue) -> DispatchIO {
        let descriptor = descriptor
        discard self
        return DispatchIO(type: .stream, fileDescriptor: descriptor, queue: queue) { _ in
            close(descriptor)
        }
    }

    /// Writes `data` without blocking, then closes the pipe so the command sees end of file. A command
    /// that never reads its input leaves the write pending until it exits; one that has exited fails it.
    consuming func write(_ data: Data?) {
        guard let data, !data.isEmpty else { return }
        let queue = DispatchQueue(label: "Exec.LocalCommandRunner.write")
        let channel = makeChannel(queue: queue)
        channel.write(offset: 0, data: data.withUnsafeBytes { DispatchData(bytes: $0) }, queue: queue) {
            done, _, _ in
            if done { channel.close() }
        }
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

    /// Records why the command stopped early and asks it, and everything it started, to stop, killing
    /// them if they're still running after a grace period. The first reason wins; stopping a process
    /// that already exited does nothing.
    func stop(_ reason: StopReason) {
        let stopped = state.withLock { state -> Bool in
            guard state.stopReason == nil else { return false }
            if state.launched {
                guard process.isRunning else { return false }
                signal(SIGTERM)
            }
            state.stopReason = reason
            return state.launched
        }
        guard stopped else { return }
        Task {
            try? await Task.sleep(for: LocalCommandRunner.stopGracePeriod)
            state.withLock { _ in
                if process.isRunning { signal(SIGKILL) }
            }
        }
    }

    /// Signals the command's process group: `Process` makes the command a group leader, so this
    /// reaches the processes a script started too (a shell that's killed leaves its children holding
    /// the output open otherwise). Only the command itself if it somehow isn't a leader.
    private func signal(_ signal: Int32) {
        let pid = process.processIdentifier
        kill(getpgid(pid) == pid ? -pid : pid, signal)
    }
}
#endif
