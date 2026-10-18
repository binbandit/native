import ACP
import Foundation
import NativeHostProtocol

enum MetaKey {
    static let hostID = "host_id"
    static let heartbeat = "heartbeat"
    static let bootTime = "boot_time"
    static let cleanShutdown = "clean_shutdown"
    static let restartReason = "restart_reason"
}

enum HostError: Error, LocalizedError {
    case unknownAgent(String)
    case unknownSession(HostSessionID)
    case agentUnavailable(String)
    case cannotLoad(String)
    case notAcceptingPrompts
    case emptyMessage
    case permissionNotPending

    var errorDescription: String? {
        switch self {
        case .unknownAgent(let id): "No agent named \(id) is set up on this host."
        case .unknownSession: "This session isn't open on the host."
        case .agentUnavailable(let name): "\(name) isn't running, so it can't take this session."
        case .cannotLoad(let name): "\(name) can't reopen sessions, so this one can't continue after a restart."
        case .notAcceptingPrompts: "This subagent only takes work from the session that started it."
        case .emptyMessage: "There's nothing to send."
        case .permissionNotPending: "That request was already answered."
        }
    }

    var rpcError: RPCError {
        RPCError(code: -32000, message: errorDescription ?? "Host error")
    }
}
