import GitHub
import SwiftUI

/// Files Changed's rows, virtualized: content as tall as the whole list, holding only the rows near
/// what's visible, each placed where `PullRequestFilesTable` says. Scrolling between rows coming
/// and going changes no layout, so it keeps up with the display (120 Hz on ProMotion); a lazy stack
/// would build and measure rows every frame to find its place.
struct PullRequestFilesStack: View {
    let model: PullRequestPageModel
    let rows: [PullRequestFilesRow]
    /// The list's width, for how many characters of code fit.
    let width: CGFloat
    let characterWidth: CGFloat
    let isShiftDown: Bool

    @Environment(\.dsCodeFont) private var codeFont
    /// The visible part of the content, in steps of `step`, so this updates every few frames
    /// rather than every frame.
    @State private var window = CGRect(x: 0, y: 0, width: 0, height: 1_200)
    @State private var measured: [String: CGFloat] = [:]
    @State private var estimates: [PullRequestFilesTable.Kind: CGFloat] = [:]
    /// Where the rows start in the scroll content (under any banner).
    @State private var rowsTop: CGFloat = 0
    /// A marker's place, for scrolling to a file whose rows may not exist yet.
    @State private var scrollTarget: CGFloat?

    /// Rows are built this far beyond each edge of the visible part, ready before they show.
    private static let overscan: CGFloat = 600
    private static let step: CGFloat = 150
    private static let contentSpace = "pullRequestFilesContent"
    private static let targetID = "scrollTarget"

    /// Temporary: the old lazy stack, to measure against.
    private static var usesLazyStack: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "gitHubExperimentLazyStack")
        #else
        false
        #endif
    }

    private struct Placed: Identifiable {
        let row: PullRequestFilesRow
        let top: CGFloat
        let isExact: Bool
        var id: String { row.id }
    }

    var body: some View {
        let lineHeight = PullRequestDiffBlockRow.lineHeight(for: codeFont)
        let table = PullRequestFilesTable(rows: rows, measured: measured, estimates: estimates) {
            exactHeight($0, lineHeight: lineHeight)
        }
        let range = Self.usesLazyStack ? 0..<0 : table.rows(
            from: window.minY - rowsTop - Self.overscan, to: window.maxY - rowsTop + Self.overscan)
        let placed = range.map { index in
            let row = rows[index]
            return Placed(row: row, top: table.offsets[index], isExact: exactHeight(row, lineHeight: lineHeight) != nil)
        }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = model.patchError {
                        NoticeBanner(
                            tone: .warning, title: "Some diffs couldn't load", detail: error.localizedDescription
                        ) {
                            Button("Try Again") { Task { await model.loadNextPatchPage() } }
                                .buttonStyle(.ds(.secondary))
                        }
                        .padding(.bottom, DS.Space.lg)
                    }
                    #if DEBUG
                    if Self.usesLazyStack {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                content(row).fileCardSlice(row.slice)
                            }
                        }
                        .coordinateSpace(.named(PullRequestPageModel.filesSpace))
                    }
                    #endif
                    ZStack(alignment: .topLeading) {
                        // Alignment guides place rows against each other; this one at the top makes
                        // their offsets count from the top of the list.
                        Color.clear.frame(width: 0, height: 0)
                        ForEach(placed) { item in
                            placedRow(item)
                        }
                        if let scrollTarget {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .alignmentGuide(.top) { _ in -scrollTarget }
                                .id(Self.targetID)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: table.total, maxHeight: table.total, alignment: .topLeading)
                    .coordinateSpace(.named(PullRequestPageModel.filesSpace))
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named(Self.contentSpace)).minY
                    } action: {
                        rowsTop = $0
                    }
                    if model.filesCursor != nil {
                        Text("Loading the rest of the \(model.totalFiles) files…")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .padding(DS.Space.lg)
                .coordinateSpace(.named(Self.contentSpace))
            }
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                let visible = geometry.visibleRect
                // Snapped to steps: the rows built only change when the view moves a step.
                let top = (visible.minY / Self.step).rounded(.down) * Self.step
                return CGRect(x: 0, y: top, width: 0, height: visible.height + Self.step)
            } action: { _, snapped in
                window = snapped
            }
            .onChange(of: model.focusedFile) { _, path in
                guard let path, let index = rows.firstIndex(where: { $0.id == "h:\(path)" }) else { return }
                model.focusedFile = nil
                scrollTarget = table.offsets[index]
                // Once the marker is in place.
                Task { @MainActor in
                    withAnimation(.dsStandard) { proxy.scrollTo(Self.targetID, anchor: .top) }
                }
            }
        }
    }

    private func placedRow(_ item: Placed) -> some View {
        content(item.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fileCardSlice(item.row.slice)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: { height in
                guard !item.isExact else { return }
                record(height, for: item.row)
            }
            .alignmentGuide(.top) { _ in -item.top }
    }

    /// A row's height when it's known without building it: a block that doesn't wrap is exactly its
    /// lines, and a footer is its spacer and the gap before the next file.
    private func exactHeight(_ row: PullRequestFilesRow, lineHeight: CGFloat) -> CGFloat? {
        switch row.kind {
        case .block(let hunk, let range) where !model.wrapsBlock(row.path, hunk, range):
            CGFloat(range.count) * lineHeight
        case .footer:
            DS.Space.xs + DS.Space.lg
        default:
            nil
        }
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

    @ViewBuilder private func content(_ row: PullRequestFilesRow) -> some View {
        switch row.kind {
        case .header(let file):
            PullRequestFileHeader(model: model, file: file)
        case .loading:
            PullRequestFileNotice(model: model, path: row.path, kind: .loading)
        case .missing(let reason):
            PullRequestFileNotice(model: model, path: row.path, kind: .missing(reason))
        case .large(let lines):
            PullRequestFileNotice(model: model, path: row.path, kind: .large(lines: lines))
        case .hunkHeader(let hunk):
            PullRequestHunkHeaderRow(hunk: hunk)
                .onAppear { model.highlight(row.path) }
        case .block(let hunk, let range):
            PullRequestDiffBlockRow(
                model: model, path: row.path, hunk: hunk, range: range,
                columns: columns(for: row.path), characterWidth: characterWidth, isShiftDown: isShiftDown)
        case .thread(let thread, let showsAnchor):
            PullRequestReviewThreadView(model: model, thread: thread, showsAnchor: showsAnchor)
                .padding(DS.Space.md)
        case .draft:
            PullRequestCommentDraftView(model: model)
                .padding(DS.Space.md)
        case .footer:
            Color.clear.frame(height: DS.Space.xs)
        }
    }

    /// Characters of code that fit beside a file's gutter: the list's width less its padding, the
    /// card's edges, the gutter and the code's own padding.
    private func columns(for path: String) -> Int {
        guard characterWidth > 0 else { return Int.max }
        let gutter =
            CGFloat(PullRequestDiffBlockText.gutterColumns(numberWidth: model.numberWidth(path))) * characterWidth
        let code = width - DS.Space.lg * 2 - 2 - gutter - 1 - DS.Space.md * 2
        return max(Int(code / characterWidth), 20)
    }
}
