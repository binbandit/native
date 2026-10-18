import Foundation
import Testing

@testable import Skills

/// A home like a real one: skills shared by linking one folder into several agents' folders, a
/// project skill that shadows a user one, a folder without SKILL.md, and agent-managed skills.
struct SkillInventoryTests {
    let sandbox: Sandbox
    let project: URL

    init() throws {
        sandbox = try Sandbox()
        project = URL(filePath: sandbox.path("work/app"), directoryHint: .isDirectory)
        let shared = try sandbox.skill(at: "stack/anatomy")
        try sandbox.link("home/.claude/skills/anatomy", to: shared)
        try sandbox.link("home/.codex/skills/anatomy", to: shared)
        try sandbox.link("home/.agents/skills/anatomy", to: shared)
        try sandbox.skill(at: "home/.claude/skills/review")
        try sandbox.skill(at: "work/app/.claude/skills/review", description: "The project's own review.")
        try sandbox.directory("home/.codex/skills/empty-runtime")
        try sandbox.skill(at: "home/.codex/skills/.system/imagegen")
        let plugin = sandbox.path("home/.claude/plugins/cache/market/helper/1.0.0")
        try sandbox.skill(at: "home/.claude/plugins/cache/market/helper/1.0.0/skills/helping")
        try LocalSkillFiles().write(
            Data(#"{"version":2,"plugins":{"helper@market":[{"scope":"user","installPath":"\#(plugin)"}]}}"#.utf8),
            toPath: sandbox.path("home/.claude/plugins/installed_plugins.json"), executable: false)
    }

    private func items(_ formats: Set<SkillAgentFormat>) -> [SkillItem] {
        let files = LocalSkillFiles()
        let roots = SkillAgentFormat.roots(
            for: formats, home: sandbox.home, environment: [:], projects: [project], files: files)
        return SkillInventory.items(SkillScanner(files: files).scan(roots))
    }

    @Test func showsALinkedSkillOnceWithEveryPlace() {
        defer { sandbox.remove() }
        let anatomy = items([.claudeCode, .codex, .pi]).first { $0.name == "anatomy" }
        #expect(anatomy?.places.count == 3)
        #expect(anatomy?.distinctFolders.count == 1)
        #expect(anatomy?.agents == [.claudeCode, .codex, .pi])
        #expect(anatomy?.problems.isEmpty == true)
        // ~/.agents/skills is read by Codex and Pi alike.
        #expect(anatomy?.places.first { $0.path.hasSuffix(".agents/skills/anatomy") }?.root.agents == [.codex, .pi])
    }

    @Test func flagsDifferentSkillsWithOneName() throws {
        defer { sandbox.remove() }
        let review = try #require(items([.claudeCode]).first { $0.name == "review" })
        #expect(review.places.first?.root.scope == .project(project))
        #expect(review.description == "The project's own review.")
        guard case .duplicate(let agent, let paths) = review.problems.last else {
            Issue.record("expected a duplicate problem, got \(review.problems)")
            return
        }
        #expect(agent == .claudeCode)
        #expect(paths.count == 2)
    }

    @Test func listsBrokenAndAgentManagedSkills() throws {
        defer { sandbox.remove() }
        let all = items([.claudeCode, .codex])
        let empty = try #require(all.first { $0.name == "empty-runtime" })
        #expect(empty.problems == [.missingSkillFile])
        #expect(empty.agents.isEmpty)
        #expect(all.first { $0.name == "imagegen" }?.scopes == [.system])
        let helping = try #require(all.first { $0.name == "helping" })
        #expect(helping.scopes == [.plugin("helper")])
        #expect(!helping.isUserManaged)
    }
}
