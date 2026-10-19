import Foundation
import Git

/// What the diff pane can show for the selected change.
nonisolated enum GitDiffContent: Equatable, Sendable {
    case text(GitDiffText)
    /// Big enough that diffing and drawing it takes a moment, so it waits for Load Diff. Lines are
    /// git's count of changed lines when known; the size is the larger side's, in bytes.
    case collapsed(changedLines: Int?, size: Int)
    case binary
    /// Too big to diff line by line; the size is in bytes.
    case tooLarge(Int)
    case submodule
    case unavailable(String)

    /// Line diffs past this size are slow to compute and unreadable in a side panel.
    static let sizeLimit = 300 * 1024
    /// Changes past either of these show collapsed until the user asks for them.
    static let collapseSize = 96 * 1024
    static let collapseLines = 600

    /// A diff and the fingerprint of the two sides it was made from (`FileVersions.fingerprint`).
    struct Loaded: Sendable {
        let content: GitDiffContent
        /// `nil` when the sides couldn't be read.
        let fingerprint: Int?
    }

    /// Reads both sides of `change` and diffs them, off the main thread, or returns `nil` when
    /// they still match `unchanged`: a rescan rechecks the file on screen this way, since an edit
    /// can keep its line counts. A big change comes back `.collapsed` unless `expanded`; anything
    /// smaller comes back highlighted too, so the pane draws it once, in color. An expanded one
    /// shows plain first rather than wait for its colors.
    @concurrent
    static func load(
        _ change: FileChange, from repository: Repository, expanded: Bool, unlessStill unchanged: Int? = nil
    ) async -> Loaded? {
        // A submodule's entry is all there is to show.
        if change.isSubmodule { return unchanged == 0 ? nil : Loaded(content: .submodule, fingerprint: 0) }
        let versions: FileVersions
        do {
            versions = try await repository.versions(of: change)
        } catch {
            return Loaded(content: .unavailable(error.localizedDescription), fingerprint: nil)
        }
        let fingerprint = versions.fingerprint
        guard fingerprint != unchanged else { return nil }
        return Loaded(content: await content(of: change, versions, expanded: expanded), fingerprint: fingerprint)
    }

    private static func content(of change: FileChange, _ versions: FileVersions, expanded: Bool) async -> Self {
        let changedLines = change.stats.map { $0.additions + $0.deletions }
        if versions.isBinary { return .binary }
        if versions.size > sizeLimit { return .tooLarge(versions.size) }
        let isBig = versions.size > collapseSize || (changedLines ?? 0) > collapseLines
        if isBig, !expanded { return .collapsed(changedLines: changedLines, size: versions.size) }
        let (path, oldText, newText) = (change.path, versions.oldText, versions.newText ?? "")
        let layout =
            isBig
            ? DiffLayout(oldText: oldText, newText: newText)
            : await DiffLayout(path: path, oldText: oldText, newText: newText)
        return .text(GitDiffText(path: path, oldText: oldText, newText: newText, layout: layout))
    }
}

/// A text change's two sides and the rows the diff pane draws for them.
nonisolated struct GitDiffText: Equatable, Sendable {
    let path: String
    let oldText: String?
    let newText: String
    let layout: DiffLayout

    init(path: String, oldText: String?, newText: String, layout: DiffLayout? = nil) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
        self.layout = layout ?? DiffLayout(oldText: oldText, newText: newText)
    }

    /// The layout follows from the texts.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path && lhs.oldText == rhs.oldText && lhs.newText == rhs.newText
    }
}
