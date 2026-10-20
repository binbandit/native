import GitHub
import SwiftUI

/// Lines of a hunk drawn as two platform text views, the gutter and the code, with the per-line
/// tints painted behind them. Every line is `lineHeight` tall, so the block's size is known without
/// laying out text. Hovering a line shows "+" in its gutter. Clicking the gutter comments on that
/// line; dragging in it (after a long press on iPad) picks lines across blocks of the hunk, and
/// shift-click widens the comment being written. The context menu acts on the line under the pointer.
struct PullRequestDiffBlock: View {
    let model: PullRequestPageModel
    let path: String
    let hunk: DiffHunk
    let range: Range<Int>
    let text: PullRequestDiffBlockText
    /// Changes when the text does; compared instead of the texts themselves.
    let textKey: String
    let isShiftDown: Bool
    let lineHeight: CGFloat
    let gutterWidth: CGFloat

    @State private var hovered: Int?

    var body: some View {
        let lines = text.kinds.count
        HStack(alignment: .top, spacing: 0) {
            PlatformCodeText(
                text: text.gutter, key: textKey, lineCount: lines, lineHeight: lineHeight, isSelectable: false
            )
            .equatable()
            .frame(width: gutterWidth, alignment: .leading)
            .overlay(alignment: .topTrailing) { plus }
            .overlay {
                // Above the text view, which lets clicks through, so SwiftUI takes them.
                Color.clear
                    .contentShape(.rect)
                    .gesture(gutterGesture)
                    .help("Click a line number to comment on it, or drag across line numbers to comment on several")
            }
            .accessibilityHidden(true)
            SeparatorLine(axis: .vertical)
            // Lines are cut off at the pane edge rather than scrolling sideways: a nested scroll
            // view would swallow the mouse wheel meant for the page. Clicking a "…" opens the line.
            PlatformCodeText(text: text.code, key: textKey, lineCount: lines, lineHeight: lineHeight) { url in
                if let index = PullRequestDiffBlockText.expandedLine(url) {
                    model.expandLine(path, hunk, range.lowerBound + index)
                }
            }
            .equatable()
            .padding(.horizontal, DS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: CGFloat(lines) * lineHeight)
        .background(alignment: .topLeading) { tints }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .named(PullRequestPageModel.filesSpace)).minY
        } action: { minY in
            model.placeBlock(path, hunk, range, minY: minY)
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): hovered = index(at: location.y)
            case .ended: hovered = nil
            }
        }
        .contextMenu {
            if let index = hovered ?? range.last.map({ $0 - range.lowerBound }) {
                PullRequestDiffLineMenu(
                    model: model, path: path, hunk: hunk, line: range.lowerBound + index,
                    isCutOff: text.cutOff.contains(index))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Comment on These Lines") {
            if let last = range.last, let anchor = anchor(last) { model.beginComment(at: anchor) }
        }
        .accessibilityActions {
            if !text.cutOff.isEmpty {
                Button("Show Whole Lines") {
                    for index in text.cutOff { model.expandLine(path, hunk, range.lowerBound + index) }
                }
            }
        }
    }

    /// The row under a point, within the block.
    private func index(at y: CGFloat) -> Int? {
        let index = Int(y / lineHeight)
        return text.kinds.indices.contains(index) ? index : nil
    }

    private func anchor(_ line: Int) -> ReviewAnchor? {
        hunk.lines[line].anchor.map { ReviewAnchor(path: path, side: $0.side, line: $0.line) }
    }

    #if os(iOS)
    /// A tap comments on one line; press and hold, then drag, to pick several.
    private var gutterGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(
                before: DragGesture(minimumDistance: 0, coordinateSpace: .named(PullRequestPageModel.filesSpace))
            )
            .onChanged { value in
                if case .second(true, let drag?) = value { follow(drag) }
            }
            .onEnded { value in
                if case .second(true, _) = value { model.endDragSelection() }
            }
            .exclusively(
                before: SpatialTapGesture().onEnded { value in
                    if let index = index(at: value.location.y) { tapGutter(range.lowerBound + index) }
                })
    }
    #else
    /// A click comments on one line and a drag picks several; with Shift held, a click widens the
    /// comment being written instead.
    private var gutterGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(PullRequestPageModel.filesSpace))
            .onChanged { value in
                if !isShiftDown { follow(value) }
            }
            .onEnded { value in
                guard isShiftDown else { return model.endDragSelection() }
                let line = model.hunkLine(at: value.location.y, path, hunk, lineHeight: lineHeight)
                if let line, hunk.lines.indices.contains(line) { tapGutter(line) }
            }
    }
    #endif

    private func follow(_ drag: DragGesture.Value) {
        model.dragSelection(path, hunk, from: drag.startLocation.y, to: drag.location.y, lineHeight: lineHeight)
    }

    /// Comments on hunk line `line`, or with Shift held widens the comment being written to it.
    private func tapGutter(_ line: Int) {
        guard model.page?.isOpen == true, let anchor = anchor(line) else { return }
        if isShiftDown, let extended = model.extendedDraft(to: hunk.lines[line], in: hunk, path: path) {
            model.draft?.anchor = extended
            model.draft?.lines = model.lineText(for: extended)
        } else {
            model.beginComment(at: anchor)
        }
    }

    /// GitHub's "+" on the hovered line's gutter.
    @ViewBuilder private var plus: some View {
        if let hovered, model.page?.isOpen == true, anchor(range.lowerBound + hovered) != nil {
            Image(systemName: "plus.square.fill")
                .font(.system(size: DS.Size.navIcon))
                .foregroundStyle(Color.dsAccent)
                .frame(height: lineHeight)
                .offset(y: CGFloat(hovered) * lineHeight)
                .allowsHitTesting(false)
        }
    }

    /// Each line's tint (added, removed, being picked or in the comment being written, under the
    /// conversation that's highlighted, hovered) and change bar.
    private var tints: some View {
        let picked = model.draftLines(in: path, hunk: hunk).union(model.selectedLines(in: path, hunk: hunk))
        let discussed = model.highlightedThreadLines(in: path, hunk: hunk)
        let kinds = text.kinds
        let height = lineHeight
        let hovered = hovered
        let start = range.lowerBound
        return Canvas { context, size in
            for (index, kind) in kinds.enumerated() {
                let row = CGRect(x: 0, y: CGFloat(index) * height, width: size.width, height: height)
                if picked.contains(start + index) {
                    context.fill(Path(row), with: .color(.dsAccentSubtle))
                } else if discussed.contains(start + index) {
                    context.fill(Path(row), with: .color(Color.dsAttention.opacity(0.16)))
                } else if let tint = Self.tint(kind) {
                    context.fill(Path(row), with: .color(tint.opacity(0.12)))
                }
                if index == hovered {
                    context.fill(Path(row), with: .color(.dsHover))
                }
                if let tint = Self.tint(kind) {
                    context.fill(Path(CGRect(x: 0, y: row.minY, width: 2, height: height)), with: .color(tint))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func tint(_ kind: DiffHunk.Line.Kind) -> Color? {
        switch kind {
        case .added: .dsSuccess
        case .removed: .dsDanger
        case .context, .noNewline: nil
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Diff block - Lines picked for a comment") {
    DSPreviewPair {
        PullRequestPagePreview { model, _ in
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ForEach(model.rows.filter(\.isPreviewBlock).prefix(1)) { row in
                    PullRequestFilesRowView(model: model, row: row, width: 760, characterWidth: 7, isShiftDown: false)
                        .onAppear {
                            // A drag in the gutter over three added lines.
                            guard let hunk = model.hunks[row.path]?.first,
                                var selection = ReviewLineSelection(path: row.path, hunk: hunk, line: 7)
                            else { return }
                            selection.extend(to: 9)
                            model.lineSelection = selection
                        }
                }
            }
            .codeTextStyle(.compact)
        }
        .frame(width: 760)
    }
}
#endif
