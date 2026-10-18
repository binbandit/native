import GitHub
import SwiftUI

/// Every file's diff as one flat lazy list: headers, hunks in blocks of a few dozen lines,
/// conversations and notices are all rows, so only what's on screen is ever built, however big a
/// file is. Long lines are cut off where the pane ends, measured here.
struct PullRequestFilesList: View {
    let model: PullRequestPageModel

    @State private var width: CGFloat = 0
    @State private var characterWidth: CGFloat = 0
    @State private var isShiftDown = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = model.patchError {
                        NoticeBanner(
                            tone: .warning, title: "Some diffs couldn't load", detail: error.localizedDescription
                        ) {
                            Button("Try Again") { Task { await model.loadNextPatchPage() } }
                                .buttonStyle(.ds(.secondary))
                        }
                        .padding(.bottom, DS.Space.lg)
                    }
                    ForEach(model.rows) { row in
                        content(row)
                            .fileCardSlice(row.slice)
                    }
                    if model.filesCursor != nil {
                        Text("Loading the rest of the \(model.totalFiles) files…")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .padding(DS.Space.lg)
                .coordinateSpace(.named(PullRequestPageModel.filesSpace))
            }
            .scrollContentBackground(.hidden)
            .overlay(alignment: .bottom) { selectionLimit }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .background(alignment: .topLeading) { characterRuler }
            .trackingShift($isShiftDown)
            .onChange(of: model.focusedFile) { _, path in
                guard let path else { return }
                withAnimation(.dsStandard) { proxy.scrollTo("h:\(path)", anchor: .top) }
                model.focusedFile = nil
            }
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
                .task(id: row.path) { await model.highlight(row.path) }
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

    /// Why a drag in the gutter stops short, while it does.
    @ViewBuilder private var selectionLimit: some View {
        if let limit = model.lineSelection?.limit {
            Text(limit.explanation)
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background(.dsSurfaceRaised, in: Capsule())
                .overlay { Capsule().strokeBorder(.dsSeparator) }
                .padding(DS.Space.lg)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.updatesFrequently)
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

    /// Ten characters of code, measured once, for the width of one.
    private var characterRuler: some View {
        Text(verbatim: "0000000000")
            .codeTextStyle(.compact)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                characterWidth = $0 / 10
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Follows the Shift key, for shift-click ranges. iPadOS has no modifier tracking here; there,
    /// "Extend Comment to Here" in a line's menu does the same.
    fileprivate func trackingShift(_ isDown: Binding<Bool>) -> some View {
        #if os(macOS)
        onModifierKeysChanged(mask: .shift) { _, keys in isDown.wrappedValue = keys.contains(.shift) }
        #else
        self
        #endif
    }
}
