import ACP
import Foundation

/// The turn the changes inspector's This Turn shows: a task's latest, with the files its
/// files-changed card lists.
struct GitTurnReviewTarget: Hashable {
    let session: SessionKey
    /// When the turn began, which finds its baseline; nil for history the agent replayed.
    let startedAt: Date?
    /// The files the agent's edits touched, with the card's line counts. Paths are as the agent
    /// wrote them: usually absolute, sometimes relative to `folder`.
    let editedFiles: [TurnSummary.ChangedFile]
    /// The task's working folder.
    let folder: URL

    /// The session's latest turn, or nil before its first. Reads the whole transcript, so it's for
    /// actions, never a view's body.
    init?(latestTurnOf session: SessionModel) {
        guard let turn = session.state.turns.last else { return nil }
        self.session = session.key
        startedAt = turn.startedAt
        editedFiles = session.state.summary(of: turn).changedFiles
        folder = session.cwd
    }

    init(session: SessionKey, startedAt: Date?, editedFiles: [TurnSummary.ChangedFile], folder: URL) {
        self.session = session
        self.startedAt = startedAt
        self.editedFiles = editedFiles
        self.folder = folder
    }

    /// `path`, as the agent or the card named it, relative to the repository's `root` (as git
    /// spells it); nil when it's outside the repository.
    func relativePath(of path: String, root: URL) -> String? {
        let absolute = path.hasPrefix("/") ? path : folder.appending(path: path).path(percentEncoded: false)
        let roots = Set([
            Self.plain(root.path(percentEncoded: false)), Self.canonical(root.path(percentEncoded: false)),
        ])
        for spelling in [Self.plain(absolute), Self.canonical(absolute)] {
            for root in roots where spelling.hasPrefix(root + "/") {
                return String(spelling.dropFirst(root.count + 1))
            }
        }
        return nil
    }

    /// The edited files' paths relative to `root`, leaving out any outside the repository.
    func editedPaths(root: URL) -> Set<String> {
        Set(editedFiles.compactMap { relativePath(of: $0.path, root: root) })
    }

    private static func plain(_ path: String) -> String {
        let standardized = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    /// The path with symlinks resolved (`/tmp` is `/private/tmp`, as git reports it), as far as
    /// it exists on this Mac: a deleted file's folder still resolves.
    private static func canonical(_ path: String) -> String {
        var existing = URL(filePath: plain(path))
        var missing: [String] = []
        while existing.path(percentEncoded: false) != "/" {
            if let resolved = realpath(existing.path(percentEncoded: false), nil) {
                defer { free(resolved) }
                return ([String(cString: resolved)] + missing.reversed()).joined(separator: "/")
            }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return plain(path)
    }
}
