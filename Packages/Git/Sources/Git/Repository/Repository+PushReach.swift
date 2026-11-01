import Foundation

// What a push would change on its remote, read from the remote-tracking refs left by the last
// fetch. Nothing here fetches: the answer is as fresh as the last time this clone talked to it.
extension Repository {
    /// The default destination of a source-only refspec. Configured push mappings and sources
    /// other than local branches need more context, so they deliberately return no destination.
    public func pushBranch(for source: String, to remote: String) async throws(GitError) -> String? {
        let mappings = try await run(
            ["config", "--get-all", "remote.\(remote).push"], readOnly: true, acceptingStatus: [0, 1])
        guard mappings.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let configuredMode = try await run(
            ["config", "--get", "push.default"], readOnly: true, acceptingStatus: [0, 1])
        let mode = configuredMode.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Upstream (also called tracking) can map even an explicitly supplied source branch.
        // Unknown future modes should likewise supply no destination facts.
        guard ["", "simple", "current", "matching", "nothing"].contains(mode) else { return nil }
        let resolved = try await run(
            ["rev-parse", "--symbolic-full-name", "--verify", "--end-of-options", source], readOnly: true,
            acceptingStatus: [0, 1, 128])
        let ref = resolved.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolved.status == 0, ref.hasPrefix("refs/heads/") else { return nil }
        return String(ref.dropFirst("refs/heads/".count))
    }

    /// All destinations of this named remote, including pushurl and pushInsteadOf configuration.
    public func pushURLs(for remote: String) async throws(GitError) -> [String] {
        let output = try await run(["remote", "get-url", "--push", "--all", "--", remote], readOnly: true)
        return output.text.split(separator: "\n").map(String.init)
    }

    /// The commits `remote`'s `branch` has that `source` doesn't, newest first and at most `limit`,
    /// with how many there are in all; nil when this clone has never fetched that branch.
    public func commits(
        on branch: String, of remote: String, missingFrom source: String, limit: Int
    ) async throws(GitError) -> (total: Int, newest: [CommitSummary])? {
        let tracking = "refs/remotes/\(remote)/\(branch)"
        guard let remoteCommit = try await resolve(tracking), let sourceCommit = try await resolve(source) else {
            return nil
        }
        // Pin both reads to the same snapshot, even if a background fetch moves the tracking ref.
        let range = [remoteCommit, "^\(sourceCommit)", "--"]
        let count = try await run(["rev-list", "--count"] + range, readOnly: true).text
        let log = try await run(
            ["log", "--no-color", "--format=%h%x1f%s%x1f%ct", "--max-count=\(max(0, limit))"] + range, readOnly: true
        ).text
        let newest = log.split(separator: "\n").compactMap { line -> CommitSummary? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 3, let seconds = TimeInterval(fields[2]) else { return nil }
            return CommitSummary(
                hash: String(fields[0]), subject: String(fields[1]), date: Date(timeIntervalSince1970: seconds))
        }
        return (Int(count.trimmingCharacters(in: .whitespacesAndNewlines)) ?? newest.count, newest)
    }
}
