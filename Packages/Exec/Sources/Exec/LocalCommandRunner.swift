#if os(macOS)
import Foundation
import Synchronization

/// Runs commands on this Mac.
public struct LocalCommandRunner: CommandRunner {
    public init() {}

    public func run(_ command: Command) async throws -> CommandResult {
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

        let didTimeOut = Mutex(false)
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
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
                        if process.isRunning {
                            didTimeOut.withLock { $0 = true }
                            process.terminate()
                        }
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        // Whatever arrived after the last readability callback.
        collected.append(output.fileHandleForReading.readDataToEndOfFile(), to: \.output)
        collected.append(error.fileHandleForReading.readDataToEndOfFile(), to: \.error)

        if let timeout = command.timeout, didTimeOut.withLock({ $0 }) {
            throw CommandError.timedOut(command.executable, after: timeout)
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
