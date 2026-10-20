import ACP
import Foundation
import NativeHostProtocol

enum MetaKey {
    static let hostID = "host_id"
    static let heartbeat = "heartbeat"
    static let bootTime = "boot_time"
    static let cleanShutdown = "clean_shutdown"
    static let restartReason = "restart_reason"
    static let journaledRollback = "journaled_rollback"
    /// Where the local app makes task worktrees, when it moved them (`SyncAgentsParams`).
    static let worktreesFolder = "worktrees_folder"
}

enum HostError: Error, LocalizedError {
    case unknownAgent(String)
    case unknownSession(HostSessionID)
    case agentUnavailable(String)
    case cannotLoad(String)
    case notAcceptingPrompts
    case emptyMessage
    case permissionNotPending
    case questionNotPending
    /// The session is doing something that has to finish first; the reason says what.
    case busy(String)
    case notInQueue
    /// The client isn't trusted with this (a paired device without the grant).
    case notAuthorized(String)
    case updateUnavailable(String)
    /// A path that resolves outside everywhere clients may reach (`ProjectPaths`).
    case outsideProjects(String)
    case commandNotFound(String)
    case timedOut(String, seconds: Double)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unknownAgent(let id): "No agent named \(id) is set up on this host."
        case .unknownSession: "This session isn't open on the host."
        case .agentUnavailable(let name): "\(name) isn't running, so it can't take this session."
        case .cannotLoad(let name): "\(name) can't reopen sessions, so this one can't continue after a restart."
        case .notAcceptingPrompts: "This subagent only takes work from the session that started it."
        case .emptyMessage: "There's nothing to send."
        case .permissionNotPending: "That request was already answered."
        case .questionNotPending: "That question was already answered."
        case .busy(let reason): reason
        case .notInQueue: "That message isn't waiting to be put back any more."
        case .notAuthorized(let action): "This device isn't allowed to \(action) on this host."
        case .updateUnavailable(let reason): reason
        case .outsideProjects(let path):
            "\(path) isn't inside one of this host's projects, sessions' folders or task worktrees."
        case .commandNotFound(let executable): "\(executable) isn't installed on this host, or isn't on its PATH."
        case .timedOut(let executable, let seconds):
            "\(executable) didn't finish within \(Duration.seconds(seconds)), so the host stopped it."
        case .cancelled: "The command was stopped."
        }
    }

    var code: HostErrorCode {
        switch self {
        case .unknownAgent: .unknownAgent
        case .unknownSession: .unknownSession
        case .agentUnavailable: .agentUnavailable
        case .cannotLoad: .cannotLoad
        case .notAcceptingPrompts: .notAcceptingPrompts
        case .emptyMessage: .emptyMessage
        case .permissionNotPending: .permissionNotPending
        case .questionNotPending: .questionNotPending
        case .busy: .busy
        case .notInQueue: .notInQueue
        case .notAuthorized: .notAuthorized
        case .updateUnavailable: .updateUnavailable
        case .outsideProjects: .outsideProjects
        case .commandNotFound: .commandNotFound
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        }
    }

    var rpcError: RPCError {
        code.rpcError(errorDescription ?? "Host error")
    }
}
