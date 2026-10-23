import Foundation
import Testing

@testable import ACP

@Suite struct SidebarAskTests {
    @Test func requestClockUsesArrivalAndSurvivesToolUpdates() throws {
        let request = try Wire.params(RequestPermissionRequest.self, of: Wire.permissionRequest)
        let arrival = Date(timeIntervalSince1970: 1_000)
        var state = SessionState()
        state.requestPermission(request, id: .int(1), at: arrival)
        #expect(state.pendingPermissions.first?.permission.requestedAt == arrival)
        state.apply(.toolCall(request.toolCall), at: arrival.addingTimeInterval(300))
        #expect(state.pendingPermissions.first?.permission.requestedAt == arrival)
        state.resolvePermission(toolCallID: request.toolCall.toolCallId)
        state.requestPermission(request, id: .int(2), at: arrival.addingTimeInterval(600))
        #expect(state.pendingPermissions.first?.permission.requestedAt == arrival.addingTimeInterval(600))
    }

    @Test(arguments: [
        ("swift test --filter PermissionRequestTests", "Allow `swift test`?"),
        ("/usr/bin/git status --short", "Allow `git status`?"),
        ("ls -la", "Allow `ls`?"),
        ("swift && echo done", "Allow `swift`?"),
    ])
    func commandSummary(command: String, expected: String) {
        var call = ToolCallState(id: "test")
        call.rawInput = .object(["command": .string(command)])
        #expect(call.askSummary == expected)
    }
}
