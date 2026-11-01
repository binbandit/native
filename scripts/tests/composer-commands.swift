import ACP
import Foundation

@testable import Native

@main
@MainActor
private struct ComposerCommandChecks {
    static func main() throws {
        // codex-acp 2.2.2 advertises skills with a leading $, beside ordinary command names.
        let commands = try JSONDecoder().decode(
            [AvailableCommand].self,
            from: Data(
                #"[{"name":"review","description":"Review changes"},{"name":"$review","description":"Review skill"},{"name":"$plugin:check","description":"Check skill"}]"#
                    .utf8
            )
        ).map(ComposerSlashCommand.init)
        let native = ComposerSlashCommand(native: "clear", description: "Clear conversation")
        let all = [native] + commands
        guard let query = SlashCommandQuery(draft: "/rev"),
            let bare = SlashCommandQuery(draft: "/"),
            let prefixed = SlashCommandQuery(draft: "/$rev")
        else { fatalError("Slash queries should be accepted") }
        precondition(bare.matches(in: all) == all, "The slash list must include skills and Native commands")
        precondition(query.matches(in: all) == Array(commands.prefix(2)), "Skills must match without typing $")
        precondition(prefixed.matches(in: all) == [commands[1]], "Explicit skill queries must still match")
        precondition(Set(all.map(\.id)).count == all.count, "A skill and command can have the same base name")

        var failures = 0
        for (command, expected) in zip(all, ["/clear ", "/review ", "$review ", "$plugin:check "]) {
            let result = SlashCommandQuery.draft("/", inserting: command)
            if result.text != expected || result.cursor != result.text.endIndex {
                print(
                    "FAIL: choosing \(command.name) inserts \(result.text.debugDescription); expected \(expected.debugDescription)"
                )
                failures += 1
            }
        }
        guard failures == 0 else { exit(1) }
        print("PASS: command and skill filtering, identity, insertion and caret placement")
    }
}
