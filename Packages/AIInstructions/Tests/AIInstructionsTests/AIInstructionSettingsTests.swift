import Foundation
import Testing

@testable import AIInstructions

struct AIInstructionSettingsTests {
    let project = "/Users/me/code/shop"

    @Test func projectInstructionsReplaceGlobalOnes() {
        let settings = AIInstructionSettings(
            global: [.commitMessage: "Imperative.", .title: "Short."],
            projects: [project: [.commitMessage: "Past tense.", .title: ""]])

        #expect(settings.text(for: .commitMessage, inProject: project) == "Past tense.")
        #expect(settings.source(for: .commitMessage, inProject: project) == .project)
        // An empty custom text means none for this project, not the global one.
        #expect(settings.text(for: .title, inProject: project).isEmpty)
        #expect(settings.text(for: .commitMessage, inProject: "/elsewhere") == "Imperative.")
        #expect(settings.text(for: .branchName, inProject: project).isEmpty)
    }

    @Test func theOrganizationsInstructionsReplaceEverything() {
        let settings = AIInstructionSettings(
            global: [.commitMessage: "Imperative.", .title: "Short."],
            projects: [project: [.commitMessage: "Past tense."]],
            managed: [.commitMessage: "Start with the ticket key."])

        #expect(settings.text(for: .commitMessage, inProject: project) == "Start with the ticket key.")
        #expect(settings.source(for: .title, inProject: nil) == .organization)
        #expect(settings.text(for: .title, inProject: nil).isEmpty)
    }

    @Test func foldersInAProjectGetItsInstructions() throws {
        let settings = AIInstructionSettings(
            global: [.title: "Global."],
            projects: [project: [.title: "Shop."], project + "/packages/web": [.title: "Web."]])

        let inside = URL(filePath: project + "/Sources", directoryHint: .isDirectory)
        let nested = URL(filePath: project + "/packages/web/src", directoryHint: .isDirectory)
        let sibling = URL(filePath: project + "-admin", directoryHint: .isDirectory)
        #expect(try #require(settings.addition(for: .title, in: inside)).text == "Shop.")
        #expect(try #require(settings.addition(for: .title, in: nested)).text == "Web.")
        #expect(try #require(settings.addition(for: .title, in: sibling)).text == "Global.")
        #expect(try #require(settings.addition(for: .title, in: nil)).text == "Global.")
    }

    @Test func aTaskWorktreeBelongsToItsMainCheckout() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "ai-instructions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let main = base.appending(path: "shop", directoryHint: .isDirectory)
        let worktree = base.appending(path: "worktrees/shop/k3f9x", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: main.appending(path: ".git/worktrees/k3f9x"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: worktree.appending(path: "Sources"), withIntermediateDirectories: true)
        let gitdir = main.appending(path: ".git/worktrees/k3f9x").path(percentEncoded: false)
        try "gitdir: \(gitdir)\n".write(to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)

        let key = AIInstructionProject.key(for: main)
        let settings = AIInstructionSettings(projects: [key: [.branchName: "Prefix with shop/."]])

        #expect(AIInstructionProject.key(containing: worktree, among: [key]) == key)
        let addition = settings.addition(for: .branchName, in: worktree.appending(path: "Sources"))
        #expect(try #require(addition).text == "Prefix with shop/.")
        #expect(AIInstructionProject.key(containing: main, among: [key]) == key)
    }

    @Test func propertyListsSkipUnknownPurposes() {
        let purposes = AIInstructionSettings.purposes(["title": "Short.", "haiku": "5-7-5"])
        #expect(purposes == [.title: "Short."])
        #expect(AIInstructionSettings.propertyList(purposes) == ["title": "Short."])
    }
}
