import Foundation
import Synchronization

/// What a finished process printed.
struct ProcessOutput: Sendable {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data
}

/// Runs a process to completion without blocking a thread: pipes drain on their dispatch handlers
/// (so a chatty process can't fill a pipe and stall), and the result arrives once the process has
/// exited and both pipes are closed. Cancelling the task, or running past `timeout`, terminates it.
enum ProcessRunner {
    struct TimedOut: Error {}

    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        directory: URL?,
        input: Data?,
        timeout: Duration
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = input.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin ?? FileHandle.nullDevice

        let collector = Collector()
        let deadline = Task {
            try await Task.sleep(for: timeout)
            collector.timeOut()
            // `terminate()` raises for a process that never launched.
            if process.isRunning { process.terminate() }
        }
        defer { deadline.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.start(continuation)
                guard !Task.isCancelled else {
                    collector.fail(CancellationError())
                    return
                }
                stdout.fileHandleForReading.readabilityHandler = { collector.read($0, into: \.stdout) }
                stderr.fileHandleForReading.readabilityHandler = { collector.read($0, into: \.stderr) }
                process.terminationHandler = { collector.exited($0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    collector.fail(error)
                    return
                }
                if let stdin, let input {
                    // gh reads all of stdin before doing anything, and the pipes drain on their
                    // own queues meanwhile, so a blocking write can't deadlock.
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Gathers output and resumes the caller once the process has exited and both pipes hit EOF.
    private final class Collector: Sendable {
        struct State {
            var stdout = Data()
            var stderr = Data()
            var openPipes = 2
            var exitCode: Int32?
            var timedOut = false
            var continuation: CheckedContinuation<ProcessOutput, any Error>?
        }

        private let state = Mutex(State())

        func start(_ continuation: CheckedContinuation<ProcessOutput, any Error>) {
            state.withLock { $0.continuation = continuation }
        }

        func read(_ handle: FileHandle, into buffer: WritableKeyPath<State, Data>) {
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                finish { $0.openPipes -= 1 }
            } else {
                state.withLock { $0[keyPath: buffer].append(data) }
            }
        }

        func exited(_ exitCode: Int32) {
            finish { $0.exitCode = exitCode }
        }

        func timeOut() {
            state.withLock { $0.timedOut = true }
        }

        func fail(_ error: any Error) {
            let continuation = state.withLock { state in
                defer { state.continuation = nil }
                return state.continuation
            }
            continuation?.resume(throwing: error)
        }

        private func finish(_ update: (inout State) -> Void) {
            let completion: (CheckedContinuation<ProcessOutput, any Error>, Result<ProcessOutput, any Error>)? = state.withLock { state in
                update(&state)
                guard state.openPipes == 0, let exitCode = state.exitCode, let continuation = state.continuation else {
                    return nil
                }
                state.continuation = nil
                let output = ProcessOutput(exitCode: exitCode, stdout: state.stdout, stderr: state.stderr)
                return (continuation, state.timedOut ? .failure(TimedOut()) : .success(output))
            }
            if let (continuation, result) = completion {
                continuation.resume(with: result)
            }
        }
    }
}
