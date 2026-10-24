import Testing

@testable import ACP

@Suite struct QuickApprovalTests {
    @Test(arguments: ["swift test", "swift test --filter PermissionRequestTests", "swift build", "git status --short"])
    func routine(command: String) {
        var call = ToolCallState(id: "ask")
        call.rawInput = .object(["command": .string(command)])
        #expect(call.allowsQuickApproval)
    }

    @Test(arguments: [
        "git push --force origin main", "git push origin main", "rm -rf build", "unknown-tool",
        "swift test; git push", "swift test\ngit push", "swift test && rm -rf build",
        "swift test --filter $(rm -rf build)", "swift test --filter `touch sent`", "swift test > result",
        "swift test --package-path elsewhere", "/tmp/swift test", "env swift test", "swift test --filter --parallel",
    ])
    func reviewRequired(command: String) {
        var call = ToolCallState(id: "ask")
        call.rawInput = .object(["command": .string(command)])
        #expect(!call.allowsQuickApproval)
    }

    @Test func planAndUnknownToolNeedReview() {
        var call = ToolCallState(id: "ask")
        #expect(!call.allowsQuickApproval)
        call.kind = .switchMode
        call.rawInput = .object(["command": .string("swift test")])
        #expect(!call.allowsQuickApproval)
    }
}
