import Foundation
import Testing

@testable import ApprovalAnalysis

@Suite struct CommandKnowledgeTests {
    @Test func bundledDataIsValid() {
        #expect(CommandKnowledge.bundled.problems == [])
        #expect(CommandKnowledge.bundled.programs.count == 36)
    }

    @Test(arguments: CommandCoverageExamples.commands)
    func realCommandLines(command: String, destructive: Bool) {
        let result = ApprovalCommand(command: command, workingDirectory: "/repo")
        #expect(result.risk == (destructive ? .irreversible : .routine), "\(command)")
        #expect(!result.parts.isEmpty)
        #expect(result.command == command)
        let characters = Array(command)
        var end = 0
        for part in result.parts {
            #expect(part.range.lowerBound >= end)
            #expect(part.range.upperBound <= characters.count)
            #expect(!part.explanation.isEmpty)
            end = part.range.upperBound
        }
    }

    static let internalTool =
        #"{"version":1,"programs":[{"executables":["acme-tool"],"commands":[{"words":["inspect"],"summary":"inspect {count} items","consequence":"Local inspection only.","destructive":false,"options":[],"operands":{"minimum":1,"maximum":2,"summary":"item: {value}","paths":false}}]}],"locations":[]}"#

    @Test func dataAloneAddsATool() {
        let extra = CommandKnowledge.load(Data(Self.internalTool.utf8))
        #expect(extra.problems.isEmpty)
        let combined = CommandKnowledge.bundled.adding(extra, source: "Test plugin")
        let result = ApprovalCommand(
            command: "acme-tool inspect example", workingDirectory: "/repo", knowledge: combined)
        #expect(result.action == "inspect 1 items")
        #expect(result.parts.last?.explanation == "item: example")
        #expect(result.risk == .routine)
        #expect(
            ApprovalCommand(command: "acme-tool destroy example", workingDirectory: "/repo", knowledge: combined).risk
                == .unknown)
    }

    @Test(arguments: [
        ("\"version\":1", "\"version\":2"),
        ("\"destructive\":false", "\"destructive\":\"false\""),
        ("inspect {count} items", "inspect {guess} items"),
        ("\"maximum\":2", "\"maximum\":0"),
        ("\"options\":[]", "\"options\":[],\"optoins\":[]"),
        ("\"acme-tool\"", "\"\""),
    ])
    func badEntriesAreExplained(old: String, new: String) {
        let result = CommandKnowledge.load(Data(Self.internalTool.replacingOccurrences(of: old, with: new).utf8))
        #expect(!result.problems.isEmpty)
        #expect(result.programs.isEmpty)
    }

    @Test func badEntryDoesNotDiscardGoodNeighbours() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(Self.internalTool.utf8)) as? [String: Any])
        let entries = try #require(json["programs"] as? [Any])
        json["programs"] = [["executables": ["broken"]]] + entries
        let result = CommandKnowledge.load(try JSONSerialization.data(withJSONObject: json))
        #expect(result.recognizes("acme-tool"))
        #expect(result.problems == ["Program 1: commands must contain 1 to 128 entries; ignored."])
        #expect(CommandKnowledge.load(Data("[]".utf8)).programs.isEmpty)
        #expect(!CommandKnowledge.load(Data(repeating: 32, count: 1_048_577)).problems.isEmpty)
    }

    @Test func contributionsCannotOverrideKnownTools() {
        let extra = CommandKnowledge.load(
            Data(Self.internalTool.replacingOccurrences(of: "acme-tool", with: "git").utf8))
        let combined = CommandKnowledge.bundled.adding(extra, source: "Organization")
        #expect(combined.problems.count == 1)
        #expect(
            ApprovalCommand(command: "git inspect example", workingDirectory: "/repo", knowledge: combined).risk
                == .unknown)
    }

    @Test(arguments: [
        "git status --invented", "find -- . -delete", "mv -R source destination", "cargo run --workspace",
        "swift build --filter Test",
        "gh pr view --squash", "docker ps --volume foo", "git -c alias.status=push status",
        "git -C /tmp status",
        "git invented", "rm -rf /tmp/a && git status", "rm -rf /tmp/*", "rm -rf $(pwd)",
        "rm -rf `pwd`", "rm -rf /tmp/a\nwhoami", "curl -o", "curl --output=", "tar -Q archive",
        "./git push origin main", "/tmp/git status", "git push -ff origin main", "acme-command --force",
        "find . -exec rm {} +", "NAME=value git status",
    ])
    func unsupportedSyntaxMakesNoClaims(_ command: String) {
        let result = ApprovalCommand(command: command, workingDirectory: "/repo")
        #expect(result.risk == .unknown)
        #expect(result.parts.isEmpty)
        #expect(result.suggestedCommand == nil)
    }

    @Test(arguments: [
        "git push --force --mirror origin", "git push --force origin +main", "git push --force --delete origin main",
        "git push --force origin :main",
    ])
    func forceOverridesBlockTheAlternative(_ command: String) {
        let result = ApprovalCommand(command: command, workingDirectory: "/repo")
        #expect(result.risk == .irreversible)
        #expect(result.suggestedCommand == nil)
    }

    @Test(arguments: [
        "git reflog delete 'HEAD@{0}'", "git reflog expire HEAD", "git reflog drop refs/heads/main",
        "git reflog write refs/heads/main abc123 def456 message",
    ])
    func reflogMutationsAreNeverHistoryDisplay(_ command: String) {
        let result = ApprovalCommand(command: command, workingDirectory: "/repo")
        #expect(result.risk == .irreversible)
        #expect(result.action != "show ref update history")
    }

    @Test func cacheNamesNeverProveContentsOrUndo() {
        for path in ["node_modules", ".build", "~/Library/Developer/Xcode/DerivedData/App"] {
            let result = ApprovalCommand(
                command: "rm -rf \(path)", workingDirectory: "/repo", homeDirectory: "/home/test")
            #expect(result.risk == .irreversible)
            #expect(result.parts.last?.explanation.contains("conventional") == true)
            #expect(result.consequence.contains("not been inspected"))
        }
        let escaped = ApprovalCommand(command: "rm -rf .build/../source", workingDirectory: "/repo")
        #expect(escaped.parts.last?.explanation.contains("conventional") == false)
        let prefix = ApprovalCommand(command: "rm -rf ../repo-copy", workingDirectory: "/repo")
        #expect(prefix.parts.last?.explanation.contains("outside") == true)
    }

    @Test func optionValuesAndTerminatorAreNotFlags() {
        let result = ApprovalCommand(command: "rm -- -rf", workingDirectory: "/repo")
        #expect(result.parts.last?.explanation.contains("path") == true)
        #expect(result.parts.count == 3)
        let quoted = ApprovalCommand(command: "git commit -m 'hello --force'", workingDirectory: "/repo")
        #expect(quoted.parts.count == 2)
        #expect(quoted.suggestedCommand == nil)
        let unicode = ApprovalCommand(command: "rm 'café 📁'", workingDirectory: "/repo")
        #expect(unicode.parts.last.map { String(Array(unicode.command)[$0.range]) } == "'café 📁'")
    }
}
