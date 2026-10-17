#if os(macOS)
import Foundation
import Synchronization

/// The runtime as a child process speaking the protocol on its stdin and stdout. It gets no
/// environment and no stderr from the host: nothing of the app's leaks into it.
final class ScriptProcessTransport: ScriptTransport {
    let frames: AsyncThrowingStream<ScriptOutboundFrame, any Error>
    private let process: Process
    private let input: FileHandle
    private let writing = Mutex(())

    /// The runtime died by a signal it didn't choose, such as a crash.
    struct Crashed: LocalizedError {
        var signal: Int32
        var errorDescription: String? { "The script runtime crashed (signal \(signal))" }
    }

    init(helper: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        process.environment = [:]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        // A runtime that exits while a tool result is on its way must not take the app down with
        // SIGPIPE; the write fails instead, and the session already knows the runtime has gone.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let (frames, continuation) = AsyncThrowingStream.makeStream(of: ScriptOutboundFrame.self)
        // The stream ends once both the output is drained and the process has exited, so the last
        // frames are never lost to the exit and a crash is reported as one.
        let ending = Mutex(Ending())
        let finish: @Sendable (_ update: (inout Ending) -> Void) -> Void = { update in
            let ended = ending.withLock { ending in
                update(&ending)
                return ending.outcome
            }
            switch ended {
            case .none: break
            case .some(.none): continuation.finish()
            case .some(.some(let error)): continuation.finish(throwing: error)
            }
        }
        let splitter = Mutex(ScriptLineSplitter())
        let decoder = JSONDecoder()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                finish { $0.drained = true }
                return
            }
            do {
                for line in try splitter.withLock({ try $0.append(data) }) {
                    continuation.yield(try decoder.decode(ScriptOutboundFrame.self, from: line))
                }
            } catch {
                handle.readabilityHandler = nil
                finish { $0.failure = error }
            }
        }
        process.terminationHandler = { process in
            let crash = process.terminationReason == .uncaughtSignal ? Crashed(signal: process.terminationStatus) : nil
            finish { $0.exited = true; $0.crash = crash }
        }
        continuation.onTermination = { _ in
            if process.isRunning { process.terminate() }
        }

        self.frames = frames
        self.process = process
        self.input = stdin.fileHandleForWriting
        try process.run()
    }

    func send(_ frame: ScriptInboundFrame) throws {
        let line = try frame.line()
        try writing.withLock { _ in try input.write(contentsOf: line) }
    }

    func terminate() {
        // SIGKILL: a runtime spinning in JavaScript won't get a chance to ignore a gentler signal.
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private struct Ending {
        var drained = false
        var exited = false
        var crash: Crashed?
        var failure: (any Error)?

        /// Nil while the stream should stay open; then how it ends.
        var outcome: (any Error)?? {
            if let failure { return .some(failure) }
            guard drained && exited else { return nil }
            return .some(crash)
        }
    }
}
#endif
