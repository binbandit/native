import Foundation
import MCP
import Observation

/// How Native's MCP server came up this launch, as far as the user needs to know: whether it had to
/// move off the port it had last time, leaving sessions the host already runs with an address that
/// no longer reaches it until they reload (`OrchestrationServerNotice`).
@Observable
final class OrchestrationServerStatus {
    struct Move: Equatable {
        var from: UInt16
        var to: UInt16
    }

    /// The server's start, once it's listening.
    private(set) var launch: MCPServerLaunch?
    /// A move that left sessions behind, until they reload or the user dismisses it.
    private(set) var move: Move?
    /// Native's host serves the tools to its sessions, so the app's server is stopped.
    private(set) var isServedByHost = false
    private var hostEpoch: UUID?

    func started(_ launch: MCPServerLaunch) {
        self.launch = launch
    }

    /// The host has sessions that were handed the old address: say so, once.
    func leftSessionsBehind() {
        guard move == nil, let launch, let from = launch.movedFrom else { return }
        move = Move(from: from, to: launch.port)
    }

    func dismiss() {
        move = nil
    }

    /// A new host process reloads the stored URLs. Reconnecting to the same process doesn't.
    func refreshedHost(epoch: UUID) {
        if let hostEpoch, hostEpoch != epoch {
            move = nil
        }
        hostEpoch = epoch
    }

    func servedByHost() {
        isServedByHost = true
        move = nil
    }
}

#if NATIVE_PREVIEWS_WIP
extension OrchestrationServerStatus {
    /// A server that had to move ports and left sessions behind, for previews. Here rather than in a
    /// file of its own because `move` can only be set from this file.
    static func preview(movedFrom from: UInt16, to: UInt16) -> OrchestrationServerStatus {
        let status = OrchestrationServerStatus()
        status.move = Move(from: from, to: to)
        return status
    }
}
#endif
