import Foundation

@testable import MCP
@testable import Native

private struct NoticeFailure: Error {
    var message: String
}

@main
@MainActor
private struct MCPRestartNoticeRegression {
    static func main() {
        do {
            try run()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func run() throws {
        let status = movedServer()
        let move = status.move
        try expect(move != nil, "The fixture did not leave sessions on the old MCP address")
        let originalHost = UUID()
        status.refreshedHost(epoch: originalHost)
        var isConfirmingRestart = false
        let restart = { pressRestartHost(status: status) { isConfirmingRestart = true } }

        restart()
        try expect(isConfirmingRestart, "Restart Host did not request confirmation")
        try expect(status.move == move, "Requesting confirmation dismissed the MCP notice before any restart")
        isConfirmingRestart = false
        try expect(status.move == move, "Cancelling the restart dismissed the MCP notice")
        restart()
        try expect(isConfirmingRestart && status.move == move, "The MCP notice cannot request another restart")
        print("PASS: requesting and cancelling a restart preserves the MCP notice")

        status.refreshedHost(epoch: originalHost)
        try expect(status.move == move, "Reconnecting to the same host dismissed the MCP notice")
        print("PASS: reconnecting to the same host preserves the MCP notice")

        // Confirmed and idle restarts both reconnect with a different host epoch.
        status.refreshedHost(epoch: UUID())
        try expect(status.move == nil, "A completed host restart did not clear the MCP notice")
        // A later restart refreshes URLs again, which must not leave a new stale notice.
        status.leftSessionsBehind()
        status.refreshedHost(epoch: UUID())
        try expect(status.move == nil, "A later host restart left the MCP notice visible")
        print("PASS: a new host clears the MCP notice after a confirmed or idle restart")

        let handedOver = movedServer()
        handedOver.servedByHost()
        try expect(handedOver.move == nil && handedOver.isServedByHost, "Host handover did not clear the MCP notice")
        print("PASS: host handover also clears the MCP notice")

        let dismissed = movedServer()
        dismissed.dismiss()
        try expect(dismissed.move == nil, "Explicit Dismiss no longer clears the MCP notice")
        print("PASS: explicit dismissal still clears the MCP notice")
    }

    private static func movedServer() -> OrchestrationServerStatus {
        let status = OrchestrationServerStatus()
        status.started(MCPServerLaunch(port: 47_822, movedFrom: 47_821))
        status.leftSessionsBehind()
        return status
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NoticeFailure(message: message) }
    }
}
