import Foundation

/// Sorts event paths into working tree files, git state that matters, and noise.
struct ChangeClassifier: Sendable {
    let root: String
    let gitDirectory: String
    let commonDirectory: String

    init(repository: Repository) {
        root = Self.canonicalPath(repository.root)
        gitDirectory = Self.canonicalPath(repository.gitDirectory)
        commonDirectory = Self.canonicalPath(repository.commonDirectory)
    }

    init(root: String, gitDirectory: String, commonDirectory: String) {
        self.root = root
        self.gitDirectory = gitDirectory
        self.commonDirectory = commonDirectory
    }

    /// The root, plus a linked worktree's git directories, which live in the main repository.
    var watchedPaths: [String] {
        var paths = [root]
        for directory in [gitDirectory, commonDirectory] where !directory.isInside(root) && !paths.contains(directory) {
            paths.append(directory)
        }
        return paths
    }

    /// The path with symlinks resolved, e.g. `/tmp` to `/private/tmp`, as FSEvents reports it.
    static func canonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard let resolved = realpath(path, nil) else {
            return path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func classify(_ paths: some Sequence<String>) -> RepositoryChange {
        var change = RepositoryChange()
        for path in paths {
            if path.isInside(gitDirectory) || path.isInside(commonDirectory) {
                if isRelevantGitPath(path) { change.gitStateChanged = true }
            } else if path.isInside(root) {
                let relative = String(path.dropFirst(root.count + 1))
                // Nested repositories' and submodules' internals, and a linked worktree's `.git` file.
                guard !relative.isEmpty, relative != ".git", !relative.hasPrefix(".git/"), !relative.contains("/.git/"),
                    !relative.hasSuffix("/.git")
                else { continue }
                change.paths.insert(relative)
            }
        }
        return change
    }

    private func isRelevantGitPath(_ path: String) -> Bool {
        if path.isInside(gitDirectory) {
            let relative = path.dropFirst(gitDirectory.count + 1)
            if ["HEAD", "index", "MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD"].contains(relative) { return true }
        }
        if path.isInside(commonDirectory) {
            let relative = path.dropFirst(commonDirectory.count + 1)
            if relative == "packed-refs" || relative.hasPrefix("refs/heads/") || relative.hasPrefix("refs/remotes/") {
                return !relative.hasSuffix(".lock")
            }
        }
        return false
    }
}

private extension String {
    /// Whether this path is strictly inside `directory`.
    func isInside(_ directory: String) -> Bool {
        count > directory.count && hasPrefix(directory) && self[index(startIndex, offsetBy: directory.count)] == "/"
    }
}
