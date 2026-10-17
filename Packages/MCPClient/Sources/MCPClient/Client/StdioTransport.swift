import Foundation
import MCP
import Synchronization

/// A local server launched for one probe, speaking newline-delimited JSON-RPC over its stdin and
/// stdout. Replies are matched to requests by id as lines arrive; the server's own requests are
/// answered on the spot.
final class StdioTransport: MCPClientTransport {
    private let process: Process
    private let input: FileHandle
    private let command: String
    private let state = Mutex(State())
    private let stderrTail = OutputTail()

    private struct State {
        var pending: [Int: CheckedContinuation<Result<JSON, ProbeError>, Never>] = [:]
        var buffer = Data()
        var isClosed = false
        var exitStatus: Int32?
    }

    /// Launches `command` through `env`, which looks it up on `environment`'s PATH the way a shell
    /// would (an app launched from the Finder has no useful PATH of its own).
    init(command: String, arguments: [String], environment: [String: String], workingDirectory: URL?) throws(ProbeError) {
        // A server that dies mid-write must surface as an error, not end the process with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        self.command = command
        process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        input = stdin.fileHandleForWriting

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.finish()
            } else {
                self?.receive(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [stderrTail] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrTail.append(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.state.withLock { $0.exitStatus = process.terminationStatus }
        }
        do {
            try process.run()
        } catch {
            throw .failure(.launch, "Couldn't launch \(command): \(error.localizedDescription)")
        }
    }

    var stderr: String {
        stderrTail.text
    }

    func request(_ method: String, params: JSON, id: Int) async throws(ProbeError) -> JSON {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<JSON, ProbeError>, Never>) in
            let isClosed = state.withLock { state in
                if !state.isClosed { state.pending[id] = continuation }
                return state.isClosed
            }
            if isClosed {
                continuation.resume(returning: .failure(exitError()))
            } else {
                write(JSONRPC.request(method, params: params, id: id))
            }
        }
        return try result.get()
    }

    func notify(_ method: String, params: JSON) async throws(ProbeError) {
        write(JSONRPC.notification(method, params: params))
    }

    /// Closes stdin, which well-behaved servers take as the signal to exit, then terminates.
    func close() async {
        try? input.close()
        guard process.isRunning else { return }
        try? await Task.sleep(for: .milliseconds(300))
        if process.isRunning {
            process.terminate()
        }
        try? await Task.sleep(for: .seconds(2))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func write(_ message: Data) {
        do {
            try input.write(contentsOf: message + Data("\n".utf8))
        } catch {
            finish()
        }
    }

    private func receive(_ data: Data) {
        let lines = state.withLock { state in
            state.buffer.append(data)
            var lines: [Data] = []
            while let newline = state.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(state.buffer[state.buffer.startIndex..<newline])
                state.buffer.removeSubrange(state.buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines {
            // Servers that log to stdout break the protocol; their stray lines are skipped.
            switch JSONRPC.decode(line) {
            case .response(let id, let result)?:
                let continuation = state.withLock { $0.pending.removeValue(forKey: id) }
                continuation?.resume(returning: result.mapError { .failure(.initialize, "The server answered with an error: \($0.message) (\($0.code)).") })
            case .request(let id, let method)?:
                write(JSONRPC.reply(to: method, id: id))
            case .notification?, nil:
                continue
            }
        }
    }

    /// Stdout closed: the server exited or is about to. Everything waiting fails.
    private func finish() {
        let pending = state.withLock { state in
            state.isClosed = true
            defer { state.pending = [:] }
            return Array(state.pending.values)
        }
        guard !pending.isEmpty else { return }
        // The exit status arrives just after stdout closes; give it a moment.
        Task {
            for _ in 0..<20 where state.withLock({ $0.exitStatus }) == nil && process.isRunning {
                try? await Task.sleep(for: .milliseconds(25))
            }
            let error = exitError()
            pending.forEach { $0.resume(returning: .failure(error)) }
        }
    }

    private func exitError() -> ProbeError {
        let status = state.withLock { $0.exitStatus } ?? (process.isRunning ? nil : process.terminationStatus)
        switch status {
        case 127?:
            return .failure(.launch, "Couldn't find \(command) on your PATH.", exitStatus: 127)
        case let status?:
            return .failure(.initialize, "The server exited with status \(status) before answering.", exitStatus: status)
        case nil:
            return .failure(.initialize, "The server closed its output before answering.")
        }
    }
}

/// Keeps the last few KB a process writes.
final class OutputTail: Sendable {
    private static let limit = 16 * 1024
    private let buffer = Mutex(Data())

    func append(_ data: Data) {
        buffer.withLock { buffer in
            buffer.append(data)
            if buffer.count > Self.limit {
                buffer.removeFirst(buffer.count - Self.limit)
            }
        }
    }

    var text: String {
        buffer.withLock { String(decoding: $0, as: UTF8.self) }
    }
}
