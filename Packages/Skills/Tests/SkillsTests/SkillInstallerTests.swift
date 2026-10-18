import Foundation
import Testing

@testable import Skills

struct SkillInstallerTests {
    let sandbox: Sandbox
    let files = LocalSkillFiles()

    init() throws {
        sandbox = try Sandbox()
    }

    private func installer(git: FakeGit = FakeGit(), http: FakeRegistryHTTP = FakeRegistryHTTP()) -> SkillInstaller {
        SkillInstaller(
            files: files, runner: git, registry: SkillsRegistry(http: http), home: sandbox.home, environment: [:],
            trash: sandbox.path("trash"))
    }

    @Test func reachesEveryAgentWithTheFewestFolders() {
        defer { sandbox.remove() }
        let targets = installer().targets(for: [.claudeCode, .codex, .pi, .openCode], scope: .user)
        #expect(targets.map(\.directory) == [sandbox.home + "/.claude/skills", sandbox.home + "/.agents/skills"])
        #expect(targets[1].agents == [.codex, .pi, .openCode])
        let project = URL(filePath: "/work/app", directoryHint: .isDirectory)
        #expect(
            installer().targets(for: [.cursor], scope: .project(project)).map(\.directory) == [
                "/work/app/.claude/skills"
            ])
        #expect(
            installer().targets(for: [.codex], scope: .project(project)).map(\.directory) == [
                "/work/app/.agents/skills"
            ])
    }

    @Test func stagesARepositoryOfSkillsWithoutItsHistory() async throws {
        defer { sandbox.remove() }
        try sandbox.skill(at: "repo/skills/one", files: ["scripts/run.sh": "#!/bin/sh\necho hi\n"])
        try sandbox.skill(at: "repo/skills/two")
        let stage = try await installer(git: FakeGit(repository: sandbox.path("repo")))
            .stage(.git(url: "https://example.com/repo.git"))
        #expect(stage.skills.map(\.name) == ["one", "two"])
        #expect(stage.revision == "abc123")
        #expect(stage.skills[0].scripts.map(\.relativePath) == ["scripts/run.sh"])
        #expect(stage.skills[0].relativePath == "skills/one")
        let checkout = try #require(stage.stagingPath) + "/checkout"
        #expect(files.itemKind(atPath: checkout + "/.git") == nil)
        installer().discard(stage)
        #expect(files.itemKind(atPath: checkout) == nil)
    }

    @Test func explainsWhyAFetchFailed() async {
        defer { sandbox.remove() }
        await #expect(throws: SkillInstallError.gitMissing) {
            try await installer(git: FakeGit(notInstalled: true)).stage(.git(url: "https://example.com/r.git"))
        }
        await #expect(throws: SkillInstallError.offline("fatal: unable to access: Could not resolve host: example.com"))
        {
            try await installer(git: FakeGit(failure: "fatal: unable to access: Could not resolve host: example.com"))
                .stage(.git(url: "https://example.com/r.git"))
        }
        try? sandbox.directory("not-a-skill/docs")
        await #expect(throws: SkillInstallError.noSkills) {
            try await installer().stage(.folder(path: sandbox.path("not-a-skill")))
        }
    }

    @Test func stagesARegistrySkillAndRefusesFilesOutsideIt() async throws {
        defer { sandbox.remove() }
        let http = FakeRegistryHTTP(responses: [
            "download/acme/tools/hello-tool": "registry-download.json",
            "download/acme/tools/sneaky": "registry-download-unsafe.json",
        ])
        let stage = try await installer(http: http).stage(.registry(source: "acme/tools", skill: "hello-tool"))
        let skill = try #require(stage.skills.first)
        #expect(skill.name == "hello-tool")
        #expect(skill.scripts.map(\.relativePath) == ["scripts/greet.sh"])
        #expect(skill.files.count == 3)
        await #expect(throws: SkillInstallError.unsafePath("../../.zshrc")) {
            try await installer(http: http).stage(.registry(source: "acme/tools", skill: "sneaky"))
        }
        await #expect(throws: SkillInstallError.offline("skills.sh couldn't be reached.")) {
            try await installer(http: FakeRegistryHTTP(offline: true)).stage(
                .registry(source: "acme/tools", skill: "x"))
        }
    }

    @Test func installsUpdatesRemovesAndUndoes() async throws {
        defer { sandbox.remove() }
        try sandbox.skill(at: "source/greeter", files: ["notes.md": "v1"])
        let installer = installer()
        let stage = try await installer.stage(.folder(path: sandbox.path("source/greeter")))
        let skill = try #require(stage.skills.first)
        let targets = installer.targets(for: [.claudeCode, .codex], scope: .user)
        let paths = try installer.install(skill, into: targets)
        #expect(paths.allSatisfy { files.itemKind(atPath: $0 + "/SKILL.md") == .file })
        #expect(throws: SkillInstallError.alreadyInstalled(paths)) { try installer.install(skill, into: targets) }

        try files.write(Data("v2".utf8), toPath: sandbox.path("source/greeter/notes.md"), executable: false)
        let updated = try #require(
            try await installer.stage(.folder(path: sandbox.path("source/greeter"))).skills.first)
        let changes = SkillInstaller.changes(from: SkillScanner(files: files).contents(of: paths[0]), to: updated.files)
        #expect(changes == SkillUpdateChanges(added: [], removed: [], changed: ["notes.md"]))
        let previous = try installer.replace(paths[0], with: updated)
        #expect(files.contents(atPath: paths[0] + "/notes.md") == Data("v2".utf8))
        try installer.restore(previous)
        #expect(files.contents(atPath: paths[0] + "/notes.md") == Data("v1".utf8))

        let removed = try installer.moveToTrash(paths[1])
        #expect(!files.exists(paths[1]))
        try installer.restore(removed)
        #expect(files.itemKind(atPath: paths[1] + "/SKILL.md") == .file)
    }

    @Test func removingALinkLeavesItsTarget() throws {
        defer { sandbox.remove() }
        let shared = try sandbox.skill(at: "stack/anatomy")
        try sandbox.link("home/.claude/skills/anatomy", to: shared)
        let entry = try installer().moveToTrash(sandbox.path("home/.claude/skills/anatomy"))
        #expect(files.itemKind(atPath: shared + "/SKILL.md") == .file)
        #expect(files.isSymbolicLink(atPath: entry.trashedPath))
    }
}

struct SkillsRegistryTests {
    @Test func searchesByInstallsFromACapturedResponse() async throws {
        let registry = SkillsRegistry(http: FakeRegistryHTTP(responses: ["api/search": "registry-search.json"]))
        let skills = try await registry.search("pdf")
        #expect(skills.first?.id == "anthropics/skills/pdf")
        #expect(skills.first?.installSource == .registry(source: "anthropics/skills", skill: "pdf"))
        #expect(skills.map { $0.installs ?? 0 } == skills.map { $0.installs ?? 0 }.sorted(by: >))
    }

    @Test func saysWhenOffline() async {
        await #expect(throws: SkillsRegistryError.offline) {
            try await SkillsRegistry(http: FakeRegistryHTTP(offline: true)).search("pdf")
        }
    }
}
