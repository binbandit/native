import Exec
import Foundation
import Skills

/// Fixture files from the test bundle.
enum Fixture {
    static func data(_ name: String) -> Data {
        // `Bundle.module` is only generated for targets with resources, which this one has.
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) } ?? Data()
    }
}

/// A throwaway home folder in the temporary directory, so tests never touch a real one.
struct Sandbox {
    let root: String

    init() throws {
        root = try LocalSkillFiles().makeTemporaryDirectory()
    }

    var home: String { root + "/home" }

    func path(_ relative: String) -> String {
        root + "/" + relative
    }

    /// Writes a skill folder with a SKILL.md, plus any other files.
    @discardableResult
    func skill(
        at relative: String, name: String? = nil, description: String? = "Does a thing. Use when asked.",
        files: [String: String] = [:]
    ) throws -> String {
        let folder = path(relative)
        let folderName = URL(filePath: folder).lastPathComponent
        var frontmatter = "---\nname: \(name ?? folderName)\n"
        if let description { frontmatter += "description: \(description)\n" }
        frontmatter += "---\n\nInstructions for \(name ?? folderName).\n"
        try LocalSkillFiles().write(Data(frontmatter.utf8), toPath: folder + "/SKILL.md", executable: false)
        for (file, contents) in files {
            try LocalSkillFiles().write(Data(contents.utf8), toPath: folder + "/" + file, executable: false)
        }
        return folder
    }

    func link(_ relative: String, to target: String) throws {
        let link = path(relative)
        try FileManager.default.createDirectory(
            atPath: URL(filePath: link).deletingLastPathComponent().path(percentEncoded: false),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
    }

    func directory(_ relative: String) throws {
        try LocalSkillFiles().createDirectory(atPath: path(relative))
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}

/// A command runner whose git "clones" by copying a folder, so install tests stay offline.
struct FakeGit: CommandRunner {
    /// What the repository holds.
    var repository: String?
    var failure: String?
    var notInstalled = false

    func run(_ command: Command) async throws -> CommandResult {
        if notInstalled { throw CommandError.notFound(command.executable) }
        if command.arguments.contains("rev-parse") {
            return CommandResult(exitCode: 0, standardOutput: Data("abc123\n".utf8), standardError: Data())
        }
        if let failure {
            return CommandResult(exitCode: 128, standardOutput: Data(), standardError: Data(failure.utf8))
        }
        guard let repository, let destination = command.arguments.last else {
            return CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data())
        }
        try LocalSkillFiles().copyItem(atPath: repository, toPath: destination)
        try LocalSkillFiles().createDirectory(atPath: destination + "/.git")
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

/// Answers registry requests with fixtures.
struct FakeRegistryHTTP: SkillsHTTPClient {
    var responses: [String: String] = [:]
    var offline = false

    func get(_ url: URL) async throws -> (Data, Int) {
        if offline { throw URLError(.notConnectedToInternet) }
        guard let fixture = responses.first(where: { url.absoluteString.contains($0.key) })?.value else {
            return (Data(), 404)
        }
        return (Fixture.data(fixture), 200)
    }
}
