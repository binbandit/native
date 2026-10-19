import Foundation

/// A file change's rows and counts, worked out before drawing. `DiffView` lays a diff out in its
/// body, which suits a tool call's edit; a whole file's change can take long enough to diff that
/// it's laid out off the main thread into one of these instead.
public nonisolated struct DiffLayout: Sendable {
    let rows: [DiffRow]
    let stats: DiffStats

    public init(oldText: String?, newText: String) {
        (rows, stats) = DiffRow.rows(oldText: oldText, newText: newText)
    }
}
