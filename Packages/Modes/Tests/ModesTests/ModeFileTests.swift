import Foundation
import Testing

@testable import Modes

struct ModeFileTests {
    @Test func readsSettingsAndInstructions() throws {
        let text = """
            ---
            name: Security Review
            symbol: lock.shield
            description: "Looks for security problems in the current changes"
            autonomy: read-only
            effort: high
            ---
            Review the current changes for security problems.

            Report each with path:line.
            """
        let parsed = try ModeFile.parse(text, fileName: "security-review.md").get()
        #expect(parsed.warnings.isEmpty)
        #expect(parsed.mode.id == .project("security-review"))
        #expect(parsed.mode.name == "Security Review")
        #expect(parsed.mode.symbol == "lock.shield")
        #expect(parsed.mode.summary == "Looks for security problems in the current changes")
        #expect(parsed.mode.settings == ModeSettings(autonomy: .readOnly, effort: "high"))
        #expect(parsed.mode.instructions == "Review the current changes for security problems.\n\nReport each with path:line.")
    }

    @Test func everySettingIsOptional() throws {
        let parsed = try ModeFile.parse("# Write docs\nDocument what changed.", fileName: "docs_writer.md").get()
        #expect(parsed.mode.name == "Docs Writer")
        #expect(parsed.mode.symbol == ModeFile.defaultSymbol)
        #expect(parsed.mode.summary == "Write docs")
        #expect(parsed.mode.settings.isEmpty)
    }

    /// A repository can make the agent more careful, never give it more freedom.
    @Test func projectsCantRaiseAutonomy() throws {
        let text = "---\nautonomy: full\n---\nShip it."
        let project = try ModeFile.parse(text, fileName: "yolo.md", source: .project).get()
        #expect(project.mode.settings.autonomy == nil)
        #expect(project.warnings.count == 1)
        let mine = try ModeFile.parse(text, fileName: "yolo.md", source: .custom).get()
        #expect(mine.mode.settings.autonomy == .full)
    }

    @Test(arguments: [
        ("---\nname: Broken\nNo end", "The settings at the top never end: add a line with just --- after them."),
        ("---\nautonomy: fast\n---\nGo.", "autonomy: fast isn't one of read-only, ask, edit, auto, full."),
        ("---\nplan: maybe\n---\nGo.", "plan: maybe should be true or false."),
        ("---\nname: Empty\n---\n\n", "There are no instructions: write what the agent should do below the settings."),
        ("---\njust words\n---\nGo.", "Line 2 isn't a setting like name: Review."),
    ])
    func problemsSayWhatToFix(text: String, reason: String) {
        #expect(throws: ModeFile.Problem(file: "broken.md", reason: reason)) {
            try ModeFile.parse(text, fileName: "broken.md").get()
        }
    }

    @Test func unknownSettingsAreIgnoredWithAWarning() throws {
        let parsed = try ModeFile.parse("---\ncolor: blue\n---\nGo.", fileName: "x.md").get()
        #expect(parsed.warnings == ["color on line 2 isn't a mode setting, so it's ignored."])
    }

    @Test func tooLargeIsRefused() {
        let text = String(repeating: "a", count: ModeFile.maximumSize + 1)
        #expect(throws: ModeFile.Problem.self) { try ModeFile.parse(text, fileName: "big.md").get() }
    }

    @Test func writesWhatItReads() throws {
        let mode = Mode(
            id: .custom("security-review"), name: "Security Review", symbol: "lock.shield", summary: "Finds holes",
            instructions: "Look for holes.", settings: ModeSettings(autonomy: .readOnly, usesPlanMode: true, model: "opus"),
            source: .custom)
        let text = ModeFile.contents(of: mode)
        let parsed = try ModeFile.parse(text, fileName: ModeFile.fileName(for: mode.name), source: .custom).get()
        #expect(parsed.mode == mode)
        #expect(ModeFile.fileName(for: "Security Review!") == "security-review.md")
    }

    @Test func projectFolderListsModesAndProblems() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "modes-\(UUID().uuidString)")
        let folder = root.appending(path: ModeFile.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\nname: Triage\n---\nSort the issues.".write(to: folder.appending(path: "a-triage.md"), atomically: true, encoding: .utf8)
        try "---\nname: triage\n---\nAgain.".write(to: folder.appending(path: "b-triage.md"), atomically: true, encoding: .utf8)
        try "---\nname: Review\n---\nMine.".write(to: folder.appending(path: "c-review.md"), atomically: true, encoding: .utf8)
        try "---\nautonomy: nope\n---\nGo.".write(to: folder.appending(path: "d-bad.md"), atomically: true, encoding: .utf8)
        try "Not a mode".write(to: folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        let modes = ProjectModes.read(in: root)
        #expect(modes.modes.map(\.mode.name) == ["Triage"])
        #expect(modes.problems.map(\.file) == ["b-triage.md", "c-review.md", "d-bad.md"])
        #expect(ProjectModes.read(in: root.appending(path: "missing")) == ProjectModes())
    }

    @Test func catalogCyclesInPickerOrder() {
        let mine = Mode(id: .custom("x"), name: "X", symbol: "x.circle", summary: "", instructions: "x", source: .custom)
        let catalog = ModeCatalog(custom: [mine])
        #expect(catalog.next(after: .build).id == .plan)
        #expect(catalog.next(after: .review).id == mine.id)
        #expect(catalog.next(after: mine.id).id == .build)
        #expect(catalog.next(after: "gone").id == .build)
    }
}
