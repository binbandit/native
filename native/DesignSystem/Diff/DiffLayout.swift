import CodeThemes
import Foundation

/// A file change's rows and counts, worked out before drawing. `DiffView` lays a diff out in its
/// body, which suits a tool call's edit; a whole file's change can take long enough to diff that
/// it's laid out off the main thread into one of these instead.
public nonisolated struct DiffLayout: Sendable {
    let rows: [DiffRow]
    let stats: DiffStats
    /// Both files' lines highlighted for the path's language, when that was done ahead too.
    let highlighted: (new: [[CodeSegment]], old: [[CodeSegment]])?

    public init(oldText: String?, newText: String) {
        (rows, stats) = DiffRow.rows(oldText: oldText, newText: newText)
        highlighted = nil
    }

    /// Also highlights both files, so the diff draws in color from its first frame instead of
    /// drawing plain and again once colored.
    public init(path: String, oldText: String?, newText: String) async {
        (rows, stats) = DiffRow.rows(oldText: oldText, newText: newText)
        guard let language = CodeLanguage.forPath(path) else {
            highlighted = nil
            return
        }
        let cache = CodeHighlightCache.shared
        async let new = cache.highlightLines(newText, language: language)
        async let old = cache.highlightLines(oldText ?? "", language: language)
        highlighted = (await new, await old)
    }
}
