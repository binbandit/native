import GitHub
import SwiftUI

/// Files Changed's rows, virtualized: content as tall as the whole list, holding only the rows near
/// what's visible, each placed where `PullRequestFilesTable` says. The table is built here, only
/// when the rows or a measured height change; scrolling moves through it in
/// `PullRequestFilesViewport` with a binary search, so a frame of scrolling does no layout.
struct PullRequestFilesStack: View {
    let model: PullRequestPageModel
    let rows: [PullRequestFilesRow]
    /// The list's width, for how many characters of code fit.
    let width: CGFloat
    let characterWidth: CGFloat
    let isShiftDown: Bool

    @Environment(\.dsCodeFont) private var codeFont
    @State private var measured: [String: CGFloat] = [:]
    @State private var estimates: [PullRequestFilesTable.Kind: CGFloat] = [:]

    var body: some View {
        let lineHeight = PullRequestDiffBlockRow.lineHeight(for: codeFont)
        let lineByLine = model.pathsDrawnLineByLine
        let table = PullRequestFilesTable(rows: rows, measured: measured, estimates: estimates) { row in
            switch row.kind {
            case .block(let hunk, let range):
                lineByLine.contains(row.path) && model.wrapsBlock(row.path, hunk, range)
                    ? nil : CGFloat(range.count) * lineHeight
            case .footer:
                DS.Space.xs + DS.Space.lg
            default:
                nil
            }
        }
        PullRequestFilesViewport(
            model: model, rows: rows, table: table, width: width, characterWidth: characterWidth,
            isShiftDown: isShiftDown, record: record)
    }

    private func record(_ height: CGFloat, for row: PullRequestFilesRow) {
        if abs((measured[row.id] ?? 0) - height) > 0.5 {
            measured[row.id] = height
        }
        // Headers, hunk headers and notices are alike: one measured stands in for the rest.
        if let kind = PullRequestFilesTable.Kind(row), [.header, .foldedHeader, .hunkHeader, .notice].contains(kind),
            abs((estimates[kind] ?? 0) - height) > 0.5
        {
            estimates[kind] = height
        }
    }
}
