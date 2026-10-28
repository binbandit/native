import Foundation
import Testing

@testable import SessionTitling

@Suite("Distinct titles")
struct DistinctTitleTests {
    @Test("A title no other task has stays as it is")
    func unique() {
        #expect(
            SessionTitleRules.distinct("Fix greet tests", from: ["Run shell command"], prompt: "fix the tests")
                == "Fix greet tests")
    }

    @Test("A title another task has is told apart by what the task's own message names")
    func byDetail() {
        #expect(
            SessionTitleRules.distinct(
                "Run shell command", from: ["Run shell command"], prompt: "run `ls -la` in the repo")
                == "Run shell command (`ls -la`)")
        #expect(
            SessionTitleRules.distinct("Add a flag", from: ["add a flag"], prompt: "add --shout to greet.py, please.")
                == "Add a flag (--shout)")
        #expect(
            SessionTitleRules.details(in: "update src/app.ts and the README for parseConfig") == [
                "parseConfig"
            ])
    }

    @Test("The same message again reads as a repeat, and only then gets a number")
    func repeats() {
        #expect(
            SessionTitleRules.distinct("Run shell command", from: ["Run shell command"], prompt: "run a shell command")
                == "Run shell command again")
        #expect(
            SessionTitleRules.distinct(
                "Run shell command", from: ["Run shell command", "Run shell command again"],
                prompt: "run a shell command") == "Run shell command (3)")
    }

    @Test("A generated title is told apart as it lands")
    func onAccept() {
        var state = SessionTitleState()
        state.begin(SessionTitleRequest(projectName: "sample", prompt: "run a shell command"))
        state.accept(generated: "run shell command", distinctFrom: ["Run shell command"])
        #expect(state.generated == "Run shell command again")
    }

    @Test("The model hears the other tasks' titles")
    func modelPrompt() {
        let request = SessionTitleRequest(
            projectName: "sample", prompt: "run a shell command", otherTitles: ["Run shell command"])
        #expect(request.modelPrompt.contains(#"Other tasks in this project are titled "Run shell command"."#))
        #expect(!SessionTitleRequest(projectName: "sample", prompt: "x").modelPrompt.contains("Other tasks"))
    }

    @Test("A task in its own worktree belongs to the project it's a worktree of")
    func worktreeProject() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "titles-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appending(path: "sample", directoryHint: .isDirectory)
        let worktree = root.appending(path: "worktrees/sample/2s2s2", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: main.appending(path: ".git/worktrees/2s2s2"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(main.path(percentEncoded: false)).git/worktrees/2s2s2\n".write(
            to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)

        let request = SessionTitleRequest(firstMessage: "fix it", attachmentNames: [], in: worktree)
        #expect(request.projectName == "sample")
        #expect(SessionTitleRules.projectKey(of: worktree) == SessionTitleRules.projectKey(of: main))
    }
}
