import Foundation
import Testing

@testable import ACP

struct PermissionAskingTests {
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
