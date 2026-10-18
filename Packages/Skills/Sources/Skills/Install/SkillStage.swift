import Exec
import Foundation

/// A skill fetched for installing, with everything in it, so the user sees its SKILL.md and its
/// scripts before Native writes anything where agents look.
public struct StagedSkill: Hashable, Sendable, Identifiable {
    public var id: String { folderPath }
    /// Where its files are now: in Native's staging folder, or the source folder itself.
    public var folderPath: String
    /// Its folder inside the source, empty when the source is the skill.
    public var relativePath: String
    public var folder: SkillFolder
    public var files: [SkillFile]

    public var name: String { folder.name }
    public var document: SkillDocument? { folder.document }
    public var scripts: [SkillFile] { files.filter(\.isScript) }

    /// The folder name it's installed under: its name when that's valid, else its own folder's.
    public var installName: String {
        let name = folder.document?.frontmatter.name ?? ""
        return SkillDocument.isValidName(name) ? name : folder.folderName
    }
}

/// What fetching a source found.
public struct SkillStage: Hashable, Sendable {
    public var source: SkillInstallSource
    /// The folder Native fetched into, removed by `SkillInstaller.discard`; nil for a local folder.
    public var stagingPath: String?
    /// The commit fetched, for git sources.
    public var revision: String?
    public var skills: [StagedSkill]
}

public enum SkillInstallError: Error, Hashable, Sendable, LocalizedError {
    case gitMissing
    case offline(String)
    case fetchFailed(String)
    case noSkills
    case unsafePath(String)
    case alreadyInstalled([String])
    case missing(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .gitMissing: "git isn't installed, so Native can't fetch the repository. Install the Xcode Command Line Tools (xcode-select --install) and try again."
        case .offline(let detail): "You're offline, so the skill couldn't be fetched. Try again when you're connected.\n\(detail)"
        case .fetchFailed(let output): "The skill couldn't be fetched.\n\(output)"
        case .noSkills: "There's no SKILL.md there, so it isn't a skill (or a collection of skills)."
        case .unsafePath(let path): "The skill has a file outside its own folder (\(path)), so Native won't install it."
        case .alreadyInstalled(let paths): "It's already installed at \(paths.joined(separator: ", ")). Update it from its row instead."
        case .missing(let path): "\(path) isn't there anymore."
        case .failed(let reason): reason
        }
    }
}

/// Fetches skills to show before installing.
struct SkillStager: Sendable {
    let files: any SkillFileSystem
    let runner: any CommandRunner
    let registry: SkillsRegistry
    let environment: [String: String]

    func stage(_ source: SkillInstallSource) async throws(SkillInstallError) -> SkillStage {
        switch source {
        case .folder(let path):
            guard files.itemKind(atPath: path) == .directory else { throw .missing(path) }
            return SkillStage(source: source, stagingPath: nil, revision: nil, skills: try skills(in: path))
        case .git(let url, let ref, let subpath):
            let staging = try temporaryDirectory()
            do {
                let checkout = SkillPaths.join(staging, "checkout")
                let revision = try await clone(url, ref: ref, into: checkout)
                let base = subpath.map { SkillPaths.join(checkout, $0) } ?? checkout
                return SkillStage(source: source, stagingPath: staging, revision: revision, skills: try skills(in: base))
            } catch {
                try? files.removeItem(atPath: staging)
                throw error
            }
        case .registry(let repository, let skill):
            let downloaded: [RegistryFile]
            do {
                downloaded = try await registry.files(source: repository, skill: skill)
            } catch .offline {
                throw .offline("skills.sh couldn't be reached.")
            } catch {
                throw .fetchFailed(error.localizedDescription)
            }
            let staging = try temporaryDirectory()
            do {
                let folder = SkillPaths.join(staging, skill)
                for file in downloaded {
                    let components = file.path.split(separator: "/")
                    guard !file.path.hasPrefix("/"), !components.contains(".."), !components.isEmpty else {
                        throw SkillInstallError.unsafePath(file.path)
                    }
                    try write(Data(file.contents.utf8), to: SkillPaths.join(folder, file.path), script: file.contents.hasPrefix("#!"))
                }
                return SkillStage(source: source, stagingPath: staging, revision: nil, skills: try skills(in: folder))
            } catch {
                try? files.removeItem(atPath: staging)
                throw (error as? SkillInstallError) ?? .failed(error.localizedDescription)
            }
        }
    }

    private func clone(_ url: String, ref: String?, into checkout: String) async throws(SkillInstallError) -> String? {
        var arguments = ["clone", "--depth", "1", "--quiet"]
        if let ref { arguments += ["--branch", ref] }
        arguments += ["--", url, checkout]
        // Never prompt for credentials: there's no terminal to answer in.
        let environment = environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { $1 }
        let result: CommandResult
        do {
            result = try await runner.run(Command("git", arguments, environment: environment, timeout: .seconds(120)))
        } catch CommandError.notFound {
            throw .gitMissing
        } catch {
            throw .fetchFailed(error.localizedDescription)
        }
        guard result.succeeded else {
            let output = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let offline = ["Could not resolve host", "Failed to connect", "Network is unreachable", "Operation timed out"]
            throw offline.contains(where: output.contains) ? .offline(output) : .fetchFailed(output)
        }
        let revision = try? await runner.run(
            Command("git", ["-C", checkout, "rev-parse", "HEAD"], environment: environment, timeout: .seconds(10)))
        // The skill's folder is copied as is, and the repository's history isn't part of it.
        try? files.removeItem(atPath: SkillPaths.join(checkout, ".git"))
        return revision.flatMap { $0.succeeded ? $0.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
    }

    /// The skills in `base`: `base` itself when it has a SKILL.md, else every folder below it
    /// that has one (a repository of skills), a few levels deep.
    func skills(in base: String) throws(SkillInstallError) -> [StagedSkill] {
        let scanner = SkillScanner(files: files)
        let root = SkillRoot(path: base, scope: .user, agents: [])
        let found = SkillFinder(files: files).folders(in: base)
        guard !found.isEmpty else { throw .noSkills }
        return found.map { path in
            StagedSkill(
                folderPath: path,
                relativePath: path == base ? "" : String(path.dropFirst(base.count + 1)),
                folder: scanner.folder(at: path, root: root),
                files: scanner.contents(of: path)
            )
        }
    }

    private func temporaryDirectory() throws(SkillInstallError) -> String {
        do {
            return try files.makeTemporaryDirectory()
        } catch {
            throw .failed("Native couldn't make a folder to fetch into: \(error.localizedDescription)")
        }
    }

    private func write(_ data: Data, to path: String, script: Bool) throws {
        try files.write(data, toPath: path, executable: script)
    }
}

/// Finds skill folders in a fetched source.
struct SkillFinder {
    let files: any SkillFileSystem
    var maximumDepth = 4

    func folders(in base: String) -> [String] {
        if files.itemKind(atPath: SkillPaths.join(base, "SKILL.md")) == .file { return [base] }
        var found: [String] = []
        var pending = [(base, 0)]
        while !pending.isEmpty {
            let (directory, depth) = pending.removeFirst()
            guard depth < maximumDepth else { continue }
            for name in (files.contentsOfDirectory(atPath: directory) ?? []).sorted()
            where !name.hasPrefix(".") && name != "node_modules" {
                let path = SkillPaths.join(directory, name)
                guard files.itemKind(atPath: path) == .directory else { continue }
                if files.itemKind(atPath: SkillPaths.join(path, "SKILL.md")) == .file {
                    found.append(path)
                } else {
                    pending.append((path, depth + 1))
                }
            }
        }
        return found
    }
}
