import Exec
import Foundation
import Synchronization

/// Starts long-lived processes a client talks to over stdin and stdout, such as local MCP servers,
/// on some machine: this Mac today, a remote Native Host later. One-shot commands go through
/// Exec's `CommandRunner` instead.
public protocol StdioLauncher: Sendable {
    /// Starts `command`; everything it does after that arrives as events. Throws
    /// `CommandError.notFound` when the executable isn't on the command's PATH.
    func launch(_ command: Command, events: @escaping @Sendable (StdioEvent) -> Void) throws -> any StdioProcess
}

public enum StdioEvent: Sendable {
    case output(Data)
    case error(Data)
    /// Stdout reached its end: the process exited or closed it.
    case outputClosed
    case exited(status: Int32)
}

public protocol StdioProcess: Sendable {
    var isRunning: Bool { get }
    func write(_ data: Data) throws
    /// Closes stdin, which well-behaved servers take as the signal to exit.
    func closeInput()
    /// SIGTERM, or SIGKILL when `force` is set.
    func terminate(force: Bool)
}

#if os(macOS)
/// Launches processes on this Mac.
public struct LocalStdioLauncher: StdioLauncher {
    public init() {}

    public func launch(_ command: Command, events: @escaping @Sendable (StdioEvent) -> Void) throws -> any StdioProcess
    {
        guard let executable = Self.resolve(command.executable, path: command.environment["PATH"]) else {
            throw CommandError.notFound(command.executable)
        }
        // A server that dies mid-write must surface as an error, not end this process with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = executable
        process.arguments = command.arguments
        process.environment = command.environment
        if let directory = command.directory {
            process.currentDirectoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        }
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let ends = PipeEnds { events(.outputClosed) }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                ends.outputEnded()
            } else {
                events(.output(data))
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                ends.errorEnded()
            } else {
                events(.error(data))
            }
        }
        process.terminationHandler = { events(.exited(status: $0.terminationStatus)) }
        try process.run()
        return LocalStdioProcess(process: process, input: stdin.fileHandleForWriting)
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

/// Holds back `outputClosed` until stderr has ended too, so a server that logs why it's exiting and
/// quits has its last words in the tail before the failure is reported. A process that keeps stderr
/// open after closing stdout (a child it left behind, say) only delays it briefly.
private final class PipeEnds: Sendable {
    private static let errorGrace: Duration = .milliseconds(200)
    private let state = Mutex((output: false, error: false, reported: false))
    private let report: @Sendable () -> Void

    init(report: @escaping @Sendable () -> Void) {
        self.report = report
    }

    func outputEnded() {
        let errorAlreadyEnded = state.withLock { state in
            state.output = true
            return state.error
        }
        if errorAlreadyEnded {
            reportOnce()
        } else {
            Task {
                try? await Task.sleep(for: Self.errorGrace)
                reportOnce()
            }
        }
    }

    func errorEnded() {
        let outputAlreadyEnded = state.withLock { state in
            state.error = true
            return state.output
        }
        if outputAlreadyEnded { reportOnce() }
    }

    private func reportOnce() {
        let first = state.withLock { state in
            defer { state.reported = true }
            return !state.reported
        }
        if first { report() }
    }
}

private struct LocalStdioProcess: StdioProcess, @unchecked Sendable {
    // `Process` is thread-safe for what's used here: state checks, signals and its pipes.
    let process: Process
    let input: FileHandle

    var isRunning: Bool { process.isRunning }

    func write(_ data: Data) throws {
        try input.write(contentsOf: data)
    }

    func closeInput() {
        try? input.close()
    }

    func terminate(force: Bool) {
        guard process.isRunning else { return }
        if force {
            kill(process.processIdentifier, SIGKILL)
        } else {
            process.terminate()
        }
    }
}
#endif
