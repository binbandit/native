import CryptoKit
import Foundation

/// One skill folder as found: where it is, what its SKILL.md says, and what's in it.
public struct SkillFolder: Hashable, Sendable, Identifiable {
    public var id: String { path }
    /// As listed in its root, which may be a symbolic link.
    public var path: String
    /// With symbolic links resolved: the same for every link to one folder.
    public var resolvedPath: String
    public var isLink: Bool
    public var root: SkillRoot
    /// Nil when the folder has no readable SKILL.md.
    public var document: SkillDocument?
    public var problems: [SkillProblem]
    /// SKILL.md's digest, to tell copies of one skill from different skills with one name.
    public var digest: String?

    public var folderName: String {
        URL(filePath: path).lastPathComponent
    }

    /// The frontmatter's name, else the folder's (what agents fall back to).
    public var name: String {
        document?.frontmatter.name ?? folderName
    }

    public var skillFile: String {
        SkillPaths.join(path, "SKILL.md")
    }
}

/// Reads skill folders from roots, through the host's files.
public struct SkillScanner: Sendable {
    let files: any SkillFileSystem

    public init(files: any SkillFileSystem) {
        self.files = files
    }

    /// Every skill folder in `roots`. A missing root is just empty.
    public func scan(_ roots: [SkillRoot]) -> [SkillFolder] {
        roots.flatMap(scan)
    }

    func scan(_ root: SkillRoot) -> [SkillFolder] {
        folders(in: root.path, depth: root.depth).map { folder(at: $0, root: root) }
    }

    private func folders(in path: String, depth: Int) -> [String] {
        guard let names = files.contentsOfDirectory(atPath: path) else { return [] }
        let children = names.filter { !$0.hasPrefix(".") }.sorted().map { SkillPaths.join(path, $0) }
            .filter { files.itemKind(atPath: $0) == .directory }
        return depth > 1 ? children.flatMap { folders(in: $0, depth: depth - 1) } : children
    }

    func folder(at path: String, root: SkillRoot) -> SkillFolder {
        let skillFile = SkillPaths.join(path, "SKILL.md")
        var folder = SkillFolder(
            path: path, resolvedPath: files.resolvingSymlinks(atPath: path), isLink: files.isSymbolicLink(atPath: path),
            root: root, document: nil, problems: [], digest: nil)
        guard files.itemKind(atPath: skillFile) == .file else {
            folder.problems = [.missingSkillFile]
            return folder
        }
        guard let data = files.contents(atPath: skillFile), let text = String(data: data, encoding: .utf8) else {
            folder.problems = [.unreadable]
            return folder
        }
        let document = SkillDocument.parse(text, folderName: folder.folderName)
        folder.document = document
        folder.problems = document.problems
        folder.digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return folder
    }

    /// Files in a skill folder, relative to it, for showing what it contains: scripts first.
    public func contents(of folderPath: String, limit: Int = 200) -> [SkillFile] {
        var found: [SkillFile] = []
        var pending = [""]
        while let relative = pending.first, found.count < limit {
            pending.removeFirst()
            let directory = relative.isEmpty ? folderPath : SkillPaths.join(folderPath, relative)
            for name in (files.contentsOfDirectory(atPath: directory) ?? []).sorted() where name != ".git" {
                let child = relative.isEmpty ? name : relative + "/" + name
                let path = SkillPaths.join(folderPath, child)
                if files.itemKind(atPath: path) == .directory {
                    pending.append(child)
                } else if found.count < limit {
                    found.append(SkillFile(file: path, relativePath: child, files: files))
                }
            }
        }
        return found.sorted { ($0.isScript ? 0 : 1, $0.relativePath) < ($1.isScript ? 0 : 1, $1.relativePath) }
    }
}

/// A file in a skill, and whether it's code an agent could run.
public struct SkillFile: Hashable, Sendable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var size: Int
    public var isExecutable: Bool
    /// A script by extension, mode or `#!`: skills can run these, so they're shown before installing.
    public var isScript: Bool
    /// Its text, when it's small UTF-8 text.
    public var text: String?

    public static let previewLimit = 256 * 1024

    public init(relativePath: String, size: Int, isExecutable: Bool, text: String?) {
        self.relativePath = relativePath
        self.size = size
        self.isExecutable = isExecutable
        self.text = text
        let scriptExtensions: Set<String> = ["sh", "bash", "zsh", "fish", "py", "js", "mjs", "cjs", "ts", "rb", "pl", "php", "swift", "go", "rs", "ps1", "bat", "cmd", "applescript", "lua"]
        isScript =
            isExecutable || scriptExtensions.contains(URL(filePath: relativePath).pathExtension.lowercased())
            || text?.hasPrefix("#!") == true
    }

    init(file path: String, relativePath: String, files: any SkillFileSystem) {
        let size = files.size(atPath: path) ?? 0
        let text =
            size <= Self.previewLimit
            ? files.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } : nil
        self.init(relativePath: relativePath, size: size, isExecutable: files.isExecutable(atPath: path), text: text)
    }
}
