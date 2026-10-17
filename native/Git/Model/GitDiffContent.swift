import ACP
import Foundation
import Git

/// What the diff pane can show for the selected change.
enum GitDiffContent: Equatable {
    case text(FileDiff)
    case binary
    /// Too big to diff line by line; the size is in bytes.
    case tooLarge(Int)
    case submodule
    case unavailable(String)

    /// Line diffs past this size are slow to compute and unreadable in a side panel (Conductor
    /// gives up at 300 KB too).
    static let sizeLimit = 300 * 1024

    init(change: FileChange, versions: FileVersions) {
        if change.isSubmodule {
            self = .submodule
        } else if versions.isBinary {
            self = .binary
        } else if versions.size > Self.sizeLimit {
            self = .tooLarge(versions.size)
        } else {
            self = .text(FileDiff(path: change.path, oldText: versions.oldText, newText: versions.newText ?? ""))
        }
    }
}
