import GitHub
import SwiftUI

/// The scrolling part of Files Changed: builds the rows near the visible part of the content and
/// places them by the table, updating only when the view moves a step, not every frame.
struct PullRequestFilesViewport: View {
    let model: PullRequestPageModel
    let rows: [PullRequestFilesRow]
    let table: PullRequestFilesTable
    let width: CGFloat
    let characterWidth: CGFloat
    let isShiftDown: Bool
    /// Reports a measured row's height.
    let record: (CGFloat, PullRequestFilesRow) -> Void

    /// The visible part of the content, snapped to steps of `step`.
    @State private var window = CGRect(x: 0, y: 0, width: 0, height: 1_200)
    /// Where the rows start in the scroll content (under any banner).
    @State private var rowsTop: CGFloat = 0
    /// A marker's place, for scrolling to a file whose rows may not exist yet.
    @State private var scrollTarget: CGFloat?

    /// Rows are built this far beyond each edge of the visible part, ready before they show.
    private static let overscan: CGFloat = 600
    private static let step: CGFloat = 150
    private static let contentSpace = "pullRequestFilesContent"
    private static let targetID = "scrollTarget"

    var body: some View {
        let range =
            Self.usesLazyStack
            ? 0..<0
            : table.rows(from: window.minY - rowsTop - Self.overscan, to: window.maxY - rowsTop + Self.overscan)
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
                                rowView(row).fileCardSlice(row.slice)
                            }
                        }
                        .coordinateSpace(.named(PullRequestPageModel.filesSpace))
                    }
                    #endif
                    ZStack(alignment: .topLeading) {
                        // Alignment guides place rows against each other; this one at the top makes
                        // their offsets count from the top of the list.
                        Color.clear.frame(width: 0, height: 0)
                        ForEach(range, id: \.self) { index in
                            placed(rows[index], top: table.offsets[index], isExact: table.isExact[index])
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

    /// Rows keep their identity by index within a stable list; a row's own id keys its measured
    /// height.
    @ViewBuilder private func placed(_ row: PullRequestFilesRow, top: CGFloat, isExact: Bool) -> some View {
        let base = rowView(row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fileCardSlice(row.slice)
            .fixedSize(horizontal: false, vertical: true)
        Group {
            if isExact {
                base
            } else {
                base.onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { height in
                    record(height, row)
                }
            }
        }
        .alignmentGuide(.top) { _ in -top }
        .id(row.id)
    }

    private func rowView(_ row: PullRequestFilesRow) -> PullRequestFilesRowView {
        PullRequestFilesRowView(
            model: model, row: row, width: width, characterWidth: characterWidth, isShiftDown: isShiftDown)
    }

    /// Temporary: the old lazy stack, to measure against.
    private static var usesLazyStack: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "gitHubExperimentLazyStack")
        #else
        false
        #endif
    }
}
