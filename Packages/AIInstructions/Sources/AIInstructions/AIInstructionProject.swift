import Foundation

/// How a folder maps to the project whose instructions apply to it. Tasks often run in a linked
/// worktree outside the project (`~/.native/worktrees/…`), so a worktree counts as part of the
/// project its main checkout is in.
public enum AIInstructionProject {
    /// The key a project's instructions are stored under: its path with symlinks resolved and no
    /// trailing slash, the same key Git settings use for a project.
    public static func key(for folder: URL) -> String {
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The key among `keys` whose project `folder` is in: the project folder itself, a folder inside
    /// it, or a linked worktree whose main checkout is one of those. The deepest project wins.
    public static func key(containing folder: URL, among keys: some Collection<String>) -> String? {
        guard !keys.isEmpty else { return nil }
        let candidates = [key(for: folder)] + (mainCheckout(ofWorktree: folder).map { [key(for: $0)] } ?? [])
        return
            keys
            .filter { key in candidates.contains { $0 == key || $0.hasPrefix(key == "/" ? key : key + "/") } }
            .max { $0.count < $1.count }
    }

    /// The main checkout of the linked worktree `folder` is in, read from the worktree's `.git` file
    /// (`gitdir: <main>/.git/worktrees/<name>`). Nil for a main checkout or anything that isn't git.
    public static func mainCheckout(ofWorktree folder: URL) -> URL? {
        var directory = folder.standardizedFileURL
        while true {
            let marker = directory.appending(path: ".git", directoryHint: .notDirectory)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path(percentEncoded: false), isDirectory: &isDirectory) {
                guard !isDirectory.boolValue,
                    let contents = try? String(contentsOf: marker, encoding: .utf8),
                    let line = contents.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:")
                else { return nil }
                let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                let gitDirectory = URL(filePath: path, directoryHint: .isDirectory, relativeTo: directory)
                    .standardizedFileURL.path(percentEncoded: false)
                guard let range = gitDirectory.range(of: "/.git/worktrees/") else { return nil }
                return URL(filePath: String(gitDirectory[..<range.lowerBound]), directoryHint: .isDirectory)
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path(percentEncoded: false) != directory.path(percentEncoded: false) else { return nil }
            directory = parent
        }
    }
}
