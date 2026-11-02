#if os(macOS)
import Exec
import Foundation

/// A local project's files from git: tracked and untracked ones, without what .gitignore excludes,
/// which stays fast on large repositories. Outside a repository it has no files to offer.
nonisolated struct GitProjectFileIndex: ProjectFileIndex {
    /// Room for a very large repository; a git that hangs (on a stale lock or a network volume) gives
    /// up rather than leaving the `@` list loading. Cancelling the listing stops git too.
    private static let timeout = Duration.seconds(20)

    let root: URL

    @concurrent
    func files() async throws -> [String] {
        try await git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
            .split(separator: "\0")
            .map(String.init)
    }

    @concurrent
    func changedFiles() async -> Set<String> {
        // Porcelain -z: "XY path\0", with a rename's original path as an extra entry.
        guard let output = try? await git(["status", "--porcelain", "-z", "--untracked-files=all"]) else {
            return []
        }
        return Set(
            output.split(separator: "\0").compactMap { entry in
                entry.count > 3 ? String(entry.dropFirst(3)) : nil
            })
    }

    /// git's output; outside a repository git fails without any, so there's nothing to list.
    private func git(_ arguments: [String]) async throws -> String {
        let command = Command(
            "/usr/bin/git", ["-C", root.path(percentEncoded: false)] + arguments,
            environment: ProcessInfo.processInfo.environment, timeout: Self.timeout)
        return try await LocalCommandRunner().run(command).output
    }
}
#endif
