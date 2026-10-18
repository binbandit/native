import Foundation
import Testing

@testable import Skills

struct SkillSwitchesTests {
    private let app = URL(filePath: "/work/app", directoryHint: .isDirectory)

    private func place(_ path: String, scope: SkillScope, agents: Set<SkillAgentFormat>) -> SkillFolder {
        SkillFolder(
            path: path, resolvedPath: path, isLink: false, root: SkillRoot(path: "", scope: scope, agents: agents),
            document: nil, problems: [], digest: "d")
    }

    private var review: SkillItem {
        SkillItem(
            key: "review", name: "review", description: nil,
            places: [
                place("/work/app/.claude/skills/review", scope: .project(app), agents: [.claudeCode]),
                place("/home/.agents/skills/review", scope: .user, agents: [.codex, .pi]),
            ],
            problems: [], agents: [.claudeCode, .codex, .pi])
    }

    @Test func projectSwitchBeatsTheGlobalOne() {
        var switches = SkillSwitches()
        switches.set(.off, for: "review", in: nil)
        switches.set(.on, for: "review", in: app)
        #expect(switches.mode(of: "review", in: app.appending(path: "Sources")) == .on)
        #expect(switches.mode(of: "review", in: URL(filePath: "/work/site")) == .off)
        switches.set(nil, for: "review", in: app)
        #expect(switches.projects.isEmpty)
        #expect(switches.mode(of: "review", in: app) == .off)
    }

    @Test func sessionOffListHasNamesAndEveryCopysFile() {
        var switches = SkillSwitches()
        switches.set(.off, for: "review", in: app)
        #expect(switches.offList(for: [review], in: URL(filePath: "/work/site")).isEmpty)
        let list = switches.offList(for: [review], in: app)
        #expect(list.names == ["review"])
        #expect(
            list.skillFiles == ["/work/app/.claude/skills/review/SKILL.md", "/home/.agents/skills/review/SKILL.md"])
    }

    @Test func processOffListOnlyReachesProjectCopiesForAProjectSwitch() {
        var switches = SkillSwitches()
        switches.set(.off, for: "review", in: app)
        #expect(switches.processOffList(for: [review]).skillFiles == ["/work/app/.claude/skills/review/SKILL.md"])
        switches.set(.off, for: "review", in: nil)
        #expect(switches.processOffList(for: [review]).skillFiles.count == 2)
    }

    @Test func saysWhichAgentsASwitchDoesntReach() {
        var switches = SkillSwitches()
        switches.set(.off, for: "review", in: app)
        let limits = switches.limitations(of: review, agents: [.claudeCode, .codex, .pi])
        #expect(limits.count == 2)
        #expect(limits.contains { $0.hasPrefix("Codex can only turn it off in every project") })
        #expect(limits.contains { $0.hasPrefix("Pi can't leave a skill out") })

        let plugin = SkillItem(
            key: "helping", name: "helping", description: nil,
            places: [place("/p/skills/helping", scope: .plugin("helper"), agents: [.claudeCode])], problems: [],
            agents: [.claudeCode])
        #expect(switches.limitations(of: plugin, agents: [.claudeCode]).first?.contains("plugins") == true)
    }

    @Test func roundTripsThroughJSON() throws {
        var switches = SkillSwitches()
        switches.set(.off, for: "review", in: app)
        let data = try JSONEncoder().encode(switches)
        #expect(try JSONDecoder().decode(SkillSwitches.self, from: data) == switches)
    }
}

struct SkillInstallSourceTests {
    @Test func readsEveryWayOfNamingASource() {
        #expect(SkillInstallSource.parse("/Users/me/skills/pdf") == .folder(path: "/Users/me/skills/pdf"))
        #expect(SkillInstallSource.parse("~/skills/pdf", home: "/Users/me") == .folder(path: "/Users/me/skills/pdf"))
        #expect(SkillInstallSource.parse("anthropics/skills") == .git(url: "https://github.com/anthropics/skills.git"))
        #expect(
            SkillInstallSource.parse("anthropics/skills#v2")
                == .git(url: "https://github.com/anthropics/skills.git", ref: "v2"))
        #expect(
            SkillInstallSource.parse("anthropics/skills/pdf") == .registry(source: "anthropics/skills", skill: "pdf"))
        #expect(
            SkillInstallSource.parse("https://skills.sh/anthropics/skills/pdf")
                == .registry(source: "anthropics/skills", skill: "pdf"))
        #expect(
            SkillInstallSource.parse("https://github.com/anthropics/skills/tree/main/skills/pdf")
                == .git(url: "https://github.com/anthropics/skills.git", ref: "main", subpath: "skills/pdf"))
        #expect(SkillInstallSource.parse("git@github.com:me/s.git") == .git(url: "git@github.com:me/s.git"))
        #expect(SkillInstallSource.parse("https://gitlab.com/me/s") == .git(url: "https://gitlab.com/me/s"))
        #expect(SkillInstallSource.parse("not a source") == nil)
        #expect(SkillInstallSource.parse("../escape/x") == nil)
    }
}
