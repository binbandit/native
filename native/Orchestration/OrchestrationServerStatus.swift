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
    /// A move that left sessions behind, until the user dismisses it.
    private(set) var move: Move?

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
}
