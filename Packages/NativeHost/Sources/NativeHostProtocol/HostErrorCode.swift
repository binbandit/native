import ACP
import Foundation

/// The host's own errors, as clients tell them apart. They travel as JSON-RPC errors with a code
/// in -33099...-33001 and `data: {"hostError": "<name>"}`, clear of -32000, which ACP uses for
/// `auth_required`. Errors an agent returned pass through untouched, codes included.
public enum HostErrorCode: String, WireEnum {
    case unknownAgent
    case unknownSession
    /// The agent isn't running and couldn't be started.
    case agentUnavailable
    /// The agent's command isn't installed.
    case agentNotInstalled
    /// The agent can't reopen sessions (no `loadSession`).
    case cannotLoad
    /// An agent's own subagent, which only its parent gives work to.
    case notAcceptingPrompts
    case emptyMessage
    case permissionNotPending
    case questionNotPending
    /// The session is doing something that has to finish first (a turn, a hidden command, a load).
    case busy
    /// Nothing removed from the queue with that id to put back.
    case notInQueue
    /// The client isn't trusted with this (a paired device without the grant).
    case notAuthorized
    case updateUnavailable
    /// A path outside the host's projects, sessions' folders and task worktrees, once resolved.
    case outsideProjects
    /// `exec/run`: the executable isn't on the host's PATH, or doesn't exist there.
    case commandNotFound
    /// `exec/run`: the command ran past its timeout and was stopped.
    case timedOut
    /// `exec/run`: the client cancelled the command (`exec/cancel`).
    case cancelled
    /// `fs/*`: nothing is at the path (`HostFileError`).
    case fileNotFound
    /// `fs/read`: more than one answer carries; read it in ranges.
    case fileTooLarge
    /// `fs/read` on a folder, a pipe or a device.
    case notAFile
    /// `fs/list` or `fs/watch` on something that isn't a folder.
    case notADirectory
    case unknown

    /// The JSON-RPC error code.
    public var code: Int {
        let order: [HostErrorCode] = [
            .unknownAgent, .unknownSession, .agentUnavailable, .agentNotInstalled, .cannotLoad, .notAcceptingPrompts,
            .emptyMessage, .permissionNotPending, .questionNotPending, .busy, .notInQueue, .notAuthorized,
            .updateUnavailable, .outsideProjects, .commandNotFound, .timedOut, .cancelled, .fileNotFound, .fileTooLarge,
            .notAFile, .notADirectory,
        ]
        return -33001 - (order.firstIndex(of: self) ?? 98)
    }

    public func rpcError(_ message: String) -> RPCError {
        RPCError(code: code, message: message, data: .object(["hostError": .string(rawValue)]))
    }

    /// The host error `error` is, or nil for anything else (an agent's error, a dropped connection).
    public init?(_ error: any Error) {
        guard let error = error as? RPCError, let name = error.data?["hostError"]?.stringValue else { return nil }
        self = HostErrorCode(rawValue: name) ?? .unknown
    }
}
