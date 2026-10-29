import Exec
import Foundation

extension Repository {
    /// Only git-ignored caches and explicitly allowed untracked env files are eligible. Commands
    /// run on the repository's host; the client never tries to read a paired host's local paths.
    public func warmWorktree(at destination: URL, settings: WorktreeWarmSettings) async throws -> WorktreeClone.Report {
        guard settings.enabled else { return WorktreeClone.Report() }
        guard let target = try await git.repository(at: destination), target.commonDirectory == commonDirectory,
            target.root != root, target.isLinkedWorktree
        else { throw GitError.unexpectedOutput("Warm setup needs a new worktree of this project.") }
        let ignored = try await run(
            ["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"], readOnly: true)
        var paths = ignored.text.split(separator: "\0").compactMap { entry -> String? in
            guard entry.hasSuffix("/") else { return nil }
            let path = String(entry.dropLast())
            return settings.matches(path) ? path : nil
        }
        // ls-files cannot descend through a wholly ignored parent with a narrower pathspec.
        // Check explicit nested choices against ignore rules and the index instead.
        for path in settings.folders where WorktreeWarmSettings.isValidFolder(path) && path.contains("/") {
            let ignoredPath = try await run(
                ["check-ignore", "--quiet", "--", path + "/"], readOnly: true, acceptingStatus: [0, 1])
            guard ignoredPath.status == 0 else { continue }
            let tracked = try await run(
                ["--literal-pathspecs", "ls-files", "-z", "--cached", "--", path], readOnly: true)
            if tracked.stdout.isEmpty { paths.append(path) }
        }
        let directories = Set(paths)
        if settings.includesEnvironmentFiles {
            let untracked = try await run(
                ["ls-files", "-z", "--others", "--", ":(glob)**/.env", ":(glob)**/.env.local"], readOnly: true)
            paths += untracked.text.split(separator: "\0").compactMap { entry in
                let path = String(entry)
                let name = path.split(separator: "/").last
                guard name == ".env" || name == ".env.local" else { return nil }
                // Don't enumerate dependencies' own env files into the task independently.
                guard
                    !path.split(separator: "/").dropLast().contains(where: {
                        WorktreeWarmSettings.commonFolders.contains(String($0))
                    })
                else { return nil }
                return path
            }
        }
        paths = Array(Set(paths)).sorted().filter { path in
            !paths.contains { path != $0 && path.hasPrefix($0 + "/") }
        }
        guard !paths.isEmpty else { return WorktreeClone.Report() }
        let request = WorktreeClone(source: root, destination: target.root, paths: paths, directories: directories)
        let result = try await git.runner.run(request.command(environment: git.environment))
        guard result.succeeded else {
            throw GitError.unexpectedOutput("This host couldn't clone the project's caches.")
        }
        return try JSONDecoder().decode(WorktreeClone.Report.self, from: result.standardOutput)
    }
}
