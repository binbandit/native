import Foundation

/// The scripts a repository commits for its tasks, one file per event in its `.native/` folder
/// (`.native/setup.sh`), read from the project's main checkout: never from a task's worktree, which
/// may hold someone else's branch.
public enum TaskScriptRepositoryFiles {
    /// Bigger than any real script; a file past it isn't read.
    static let sizeLimit = 256 * 1024

    /// The scripts in the checkout at `root`, by event. Missing, empty, unreadable and oversized files
    /// are left out.
    public static func read(at root: URL) -> [TaskScriptEvent: String] {
        TaskScriptEvent.allCases.reduce(into: [:]) { scripts, event in
            let file = root.appending(path: event.repositoryPath, directoryHint: .notDirectory)
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= sizeLimit,
                let text = try? String(contentsOf: file, encoding: .utf8),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            scripts[event] = text
        }
    }
}
