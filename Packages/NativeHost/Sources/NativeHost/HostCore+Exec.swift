import ACP
import Exec
import Foundation
import NativeHostProtocol
import Synchronization

// Commands clients run on this host (`_native/exec/*`), so Git and GitHub code runs unchanged
// against a project here. Who may and where is `HostCore+ExecAccess.swift`.
extension HostCore {
    /// Runs a command for a client with the `runCommands` grant, in one of the host's projects, with
    /// the host's login-shell environment under the client's own variables. Recorded in the activity
    /// journal before it starts. The policy is checked again once the environment is read, and a
    /// revoked policy cancels the command (`HostCore.apply`).
    func runCommand(_ params: ExecRunParams, for client: ClientLink) async throws -> ExecRunResult {
        try require(.commands)
        try requireCommandsGrant(client, to: "run commands")
        guard let runner = commandRunner else {
            throw CommandError.unavailable("This host can't run commands yet.")
        }
        let directory = try params.directory.map { try projectPath($0, for: client, to: "run commands") }
        let timeout = try params.timeout.map { seconds in
            guard seconds.isFinite, seconds > 0 else {
                throw RPCError(code: -32602, message: "A command's timeout is a number of seconds above zero.")
            }
            return Duration.seconds(seconds)
        }
        let environment = await agentEnvironment().merging(params.environment) { $1 }
        // The client may have gone while the environment was read, and nobody would stop it then.
        guard clients[client.id] != nil else { throw HostError.cancelled }
        try require(.commands)
        // Checked and claimed in one actor turn, so two requests can't share an id.
        guard client.commands[params.execID] == nil else {
            throw RPCError(code: -32602, message: "A command with id \(params.execID) is already running.")
        }
        // An audit record that can't be written means the command doesn't run.
        try journalCommand(params, in: directory, by: client)
        let command = Command(
            params.executable, params.arguments, in: directory, environment: environment,
            standardInput: params.stdin, timeout: timeout)
        let relay = ExecOutputRelay(execID: params.execID, peer: client.peer, streams: params.stream)
        let input = params.interactive == true ? CommandInput() : nil
        client.commandInputs[params.execID] = input
        let running = Task {
            if let input {
                return try await runner.run(command, input: input) { relay.receive($0) }
            }
            return try await runner.run(command) { relay.receive($0) }
        }
        client.commands[params.execID] = running
        defer {
            input?.finish()
            client.commandInputs[params.execID] = nil
            client.commands[params.execID] = nil
        }
        do {
            let result = try await running.value
            let rest = relay.remainder()
            return ExecRunResult(exitCode: result.exitCode, stdout: rest.stdout, stderr: rest.stderr)
        } catch is CancellationError {
            throw HostError.cancelled
        } catch CommandError.notFound(let executable) {
            throw HostError.commandNotFound(executable)
        } catch CommandError.timedOut(let executable, _) {
            throw HostError.timedOut(executable, seconds: params.timeout ?? 0)
        }
    }

    /// Stops a command the same client started. One that already ended, or another client's, is
    /// left alone.
    func cancelCommand(_ execID: UUID, for client: ClientLink) {
        client.commands[execID]?.cancel()
    }

    func inputCommand(_ params: ExecInputParams, for client: ClientLink) throws {
        try requireCommandsGrant(client, to: "send command input")
        guard let input = client.commandInputs[params.execID], input.send(params.data) else {
            throw RPCError(code: -32602, message: "This command isn't waiting for input, or the input is too large.")
        }
    }

    private var commandRunner: (any CommandRunner)? {
        #if os(macOS) || os(Linux)
        configuration.commands ?? LocalCommandRunner()
        #else
        configuration.commands
        #endif
    }

    /// Notes who ran what, and where. Kept out of `_native/activity` and, unless asked, out of the
    /// journal clients list: a client watching a repository runs git all the time.
    private func journalCommand(_ params: ExecRunParams, in directory: String?, by client: ClientLink) throws {
        var line = ([params.executable] + params.arguments).map(Self.shellWord).joined(separator: " ")
        if line.count > 500 {
            line = String(line.prefix(500)) + "…"
        }
        let entry = ActivityEntry(
            id: 0, at: .now, sessionID: nil, kind: .commandRun,
            subject: client.info?.name ?? (client.grants.isLocal ? "A local client" : "A paired device"),
            detail: directory.map { "\(line) in \($0)" } ?? line)
        try store.appendActivity(entry)
    }

    /// A word of a command line as a shell would need it, so the record reads unambiguously.
    private static func shellWord(_ word: String) -> String {
        let plain = word.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:,+@%".contains($0) }
        guard !plain || word.isEmpty else { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// Hands a running command's output to the client that runs it: each piece as it arrives when the
/// client streams, otherwise all of it in the answer, sent ahead in notifications whenever more than
/// `ExecRunResult.inlineLimit` is waiting. Pieces of both streams go out under one lock, in the order
/// they arrived, so neither stream's output is ever reordered.
private final class ExecOutputRelay: Sendable {
    private struct Held {
        var stdout = Data()
        var stderr = Data()
    }

    private let execID: UUID
    private let peer: JSONRPCPeer
    private let streams: Bool
    private let held = Mutex(Held())

    init(execID: UUID, peer: JSONRPCPeer, streams: Bool) {
        self.execID = execID
        self.peer = peer
        self.streams = streams
    }

    func receive(_ output: CommandOutput) {
        held.withLock { held in
            let stream: ExecStream = output.stream == .standardOutput ? .stdout : .stderr
            guard !streams else {
                send(output.data, on: stream)
                return
            }
            switch stream {
            case .stdout: held.stdout.append(output.data)
            default: held.stderr.append(output.data)
            }
            guard held.stdout.count + held.stderr.count > ExecRunResult.inlineLimit else { return }
            send(held.stdout, on: .stdout)
            send(held.stderr, on: .stderr)
            held = Held()
        }
    }

    /// What hasn't been sent, for the answer. Called once the command has ended.
    func remainder() -> (stdout: Data, stderr: Data) {
        held.withLock { held in
            defer { held = Held() }
            return (held.stdout, held.stderr)
        }
    }

    /// Writes queue on the client's channel, so this never waits on the network.
    private func send(_ data: Data, on stream: ExecStream) {
        guard !data.isEmpty else { return }
        try? peer.notify(
            HostProtocol.Method.execOutput, ExecOutputNotification(execID: execID, stream: stream, data: data))
    }
}
