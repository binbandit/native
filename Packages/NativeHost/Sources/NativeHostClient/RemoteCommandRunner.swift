import ACP
import Exec
import Foundation
import NativeHostProtocol
import Synchronization

/// Runs commands on a host (`_native/exec/run`), for code that takes a `CommandRunner`: `Git` and
/// `GitHub` work unchanged against a project on another machine.
///
/// The host runs each command with its own login-shell environment, and `Command.environment` goes
/// on top: pass only what the command needs beyond that, since this machine's PATH and HOME mean
/// nothing there (build `Git` with `environment: [:]`). `directory` is a folder on the host, inside
/// one of its projects (`NativeHostClient.addProject`). Running commands takes the `runCommands`
/// grant; without it every command fails with `CommandError.refused`.
public struct RemoteCommandRunner: CommandRunner {
    public let client: NativeHostClient

    public init(client: NativeHostClient) {
        self.client = client
    }

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
        let params = ExecRunParams(
            executable: command.executable, arguments: command.arguments, directory: command.directory,
            environment: command.environment, stdin: command.standardInput,
            timeout: command.timeout.map(Self.seconds), stream: onOutput != nil)
        // Output arrives as notifications before the answer; collect it as the answer would.
        let collected = Mutex((stdout: Data(), stderr: Data()))
        let outputs = await client.execOutputs()
        outputs.add(params.execID) { output in
            let stream: CommandOutput.Stream = output.stream == .stderr ? .standardError : .standardOutput
            collected.withLock { collected in
                if stream == .standardError {
                    collected.stderr.append(output.data)
                } else {
                    collected.stdout.append(output.data)
                }
            }
            onOutput?(CommandOutput(stream: stream, data: output.data))
        }
        defer { outputs.remove(params.execID) }

        let result: ExecRunResult
        do {
            result = try await withTaskCancellationHandler {
                try await client.call(HostProtocol.Method.execRun, params)
            } onCancel: {
                // The host stops it and everything it started, then answers `cancelled`.
                Task { [client] in try? await client.cancelCommand(params.execID) }
            }
        } catch {
            throw failure(error, running: command)
        }
        // What wasn't sent ahead comes with the answer.
        if let onOutput {
            if !result.stdout.isEmpty { onOutput(CommandOutput(stream: .standardOutput, data: result.stdout)) }
            if !result.stderr.isEmpty { onOutput(CommandOutput(stream: .standardError, data: result.stderr)) }
        }
        let (stdout, stderr) = collected.withLock { $0 }
        return CommandResult(
            exitCode: result.exitCode, standardOutput: stdout + result.stdout, standardError: stderr + result.stderr)
    }

    /// The host's answer as `LocalCommandRunner` would have failed, so callers handle one set of errors.
    private func failure(_ error: any Error, running command: Command) -> any Error {
        let host = client.transport.displayName
        if (error as? NativeHostClient.Failure) == .notConnected {
            return CommandError.unavailable("\(host) isn't connected, so \(command.executable) didn't run.")
        }
        if (error as? PeerError) == .closed {
            return CommandError.unavailable(
                "The connection to \(host) dropped while \(command.executable) ran there; it may have finished.")
        }
        switch HostErrorCode(error) {
        case .commandNotFound: return CommandError.notFound(command.executable)
        case .timedOut: return CommandError.timedOut(command.executable, after: command.timeout ?? .zero)
        case .cancelled: return CancellationError()
        case .notAuthorized, .outsideProjects: return CommandError.refused(error.localizedDescription)
        default:
            // A paired device's gateway refuses methods its grants don't cover; an older host doesn't
            // have them.
            if let error = error as? RPCError, error.code == -32601 { return CommandError.refused(error.message) }
            return error
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

extension NativeHostClient {
    /// Stops a command started with `RemoteCommandRunner`; its run then throws `CancellationError`.
    func cancelCommand(_ execID: UUID) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.execCancel, ExecCancelParams(execID: execID))
    }

    /// Every command clients ran on the host after `after` (an activity id), newest last: the host's
    /// record of who ran what, and where. Takes the `runCommands` grant.
    public func commandsRun(after: Int64? = nil, limit: Int = 200) async throws -> [ActivityEntry] {
        let entries: [ActivityEntry] = try await call(
            HostProtocol.Method.listActivity, ListActivityParams(after: after, limit: limit, includeCommands: true))
        return entries.filter { $0.kind == .commandRun }
    }

    /// The route `_native/exec/output` takes to the command it belongs to.
    func execOutputs() -> ExecOutputRoute {
        route(HostProtocol.Method.execOutput, make: ExecOutputRoute.init)
    }
}

/// Hands each `_native/exec/output` to the run waiting for it. Output for a command nobody waits for
/// any more (it was cancelled) is dropped.
final class ExecOutputRoute: HostNotificationRoute {
    typealias Receiver = @Sendable (ExecOutputNotification) -> Void

    private let receivers = Mutex<[UUID: Receiver]>([:])

    func add(_ execID: UUID, _ receiver: @escaping Receiver) {
        receivers.withLock { $0[execID] = receiver }
    }

    func remove(_ execID: UUID) {
        receivers.withLock { $0[execID] = nil }
    }

    func receive(_ message: JSONRPCPeer.Message) async {
        guard let output = try? message.params(as: ExecOutputNotification.self) else { return }
        receivers.withLock { $0[output.execID] }?(output)
    }
}
