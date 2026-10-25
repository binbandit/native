import Foundation
import Testing

@testable import ACP

struct PermissionAskingTests {
    @Test func acceptedEditsDoNotPromiseApprovalForEveryCommand() throws {
        let data = Data(#"{"value":"acceptEdits","name":"Accept edits"}"#.utf8)
        let choice = try JSONDecoder().decode(ConfigOption.SelectOption.self, from: data)
        #expect(choice.askingTitle == "Beyond allowed edits and commands")
    }

    @Test func consequencesKeepDistinctPermissionBehaviors() throws {
        let data = Data(
            #"[{"value":"read-only","name":"Read only"},{"value":"workspace-write","name":"Workspace write"},{"value":"bypassPermissions","name":"Bypass"},{"value":"dontAsk","name":"Don't ask"},{"value":"internal-review","name":"Internal review","description":"Only reviewed changes"}]"#
                .utf8)
        let choices = try JSONDecoder().decode([ConfigOption.SelectOption].self, from: data)
        #expect(
            choices.map(\.askingTitle) == [
                "Before any change", "Before leaving the worktree", "Never",
                "Refuse anything not already allowed", "Internal review",
            ])
        #expect(choices.last?.descriptionWithoutName == "Only reviewed changes")
    }
}

struct PermissionCaptionTests {
    @Test func captionsSayWhatHappensAtEachLevel() throws {
        let options = try NewSessionChoicesTests.claude()
        let mode = try #require(options.first { $0.category == "mode" })
        guard case .select(_, let choices) = mode.kind else { return }
        #expect(
            choices.map { $0.askingCaption(agentName: "Claude Code", workspace: "fix/queued-row") } == [
                "Reads freely. Asks before every edit and command.",
                "Edits files in fix/queued-row and runs common file commands freely. Asks before anything else.",
                "Create a plan before making changes",
                "Claude Code judges each action and asks only when one looks risky.",
                "Full access. Runs anything on this Mac without asking.",
            ])
    }
}
