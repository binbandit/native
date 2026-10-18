import GitHub
import SwiftUI

/// Lines of a hunk drawn as one gutter text and one code text, with the per-line tints painted
/// behind them. Hovering a line shows "+" in its gutter; clicking the gutter comments on it
/// (shift-click widens the comment), and the context menu acts on the line under the pointer.
/// Lines don't wrap, so they stay one row tall and aligned with the gutter.
struct PullRequestDiffBlock: View {
    let model: PullRequestPageModel
    let path: String
    let hunk: DiffHunk
    let range: Range<Int>
    let text: PullRequestDiffBlockText
    /// Changes when the text does; compared instead of the texts themselves.
    let textKey: String
    let isShiftDown: Bool
    /// Where a cut-off line's "…" starts, from the code's leading edge.
    let markerOffset: CGFloat

    @State private var rowHeight: CGFloat = 0
    @State private var hovered: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            PullRequestDiffBlockGutter(text: text, key: textKey)
                .equatable()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { height in
                    rowHeight = height / CGFloat(max(text.kinds.count, 1))
                }
                .overlay(alignment: .topTrailing) { plus }
                .contentShape(.rect)
                .onTapGesture(coordinateSpace: .local) { location in
                    if let index = index(at: location.y) { tapGutter(index) }
                }
                .help("Click a line number to comment on it; shift-click to widen the comment")
            SeparatorLine(axis: .vertical)
            // Clipped rather than scrolling sideways: a nested scroll view would swallow the
            // mouse wheel meant for the page. Long lines stay selectable and copyable.
            PullRequestDiffBlockCode(text: text, key: textKey)
                .equatable()
                // A click on a cut-off line's "…" shows the line whole; selection still works.
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        if let index = index(at: value.location.y), text.cutOff.contains(index),
                            value.location.x >= markerOffset
                        {
                            model.expandLine(path, hunk, range.lowerBound + index)
                        }
                    }
                )
                .padding(.horizontal, DS.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .background(alignment: .topLeading) { tints }
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
    }

    /// The row under a point, within the block.
    private func index(at y: CGFloat) -> Int? {
        guard rowHeight > 0 else { return nil }
        let index = Int(y / rowHeight)
        return text.kinds.indices.contains(index) ? index : nil
    }

    private func anchor(_ line: Int) -> ReviewAnchor? {
        hunk.lines[line].anchor.map { ReviewAnchor(path: path, side: $0.side, line: $0.line) }
    }

    private func tapGutter(_ index: Int) {
        let line = range.lowerBound + index
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
        if let hovered, rowHeight > 0, model.page?.isOpen == true, anchor(range.lowerBound + hovered) != nil {
            Image(systemName: "plus.square.fill")
                .font(.system(size: DS.Size.navIcon))
                .foregroundStyle(Color.dsAccent)
                .frame(height: rowHeight)
                .offset(y: CGFloat(hovered) * rowHeight)
                .allowsHitTesting(false)
        }
    }

    /// Each line's tint (added, removed, in the comment being written, hovered) and change bar.
    private var tints: some View {
        let draftLines = model.draftLines(in: path, hunk: hunk)
        let kinds = text.kinds
        let height = rowHeight
        let hovered = hovered
        let start = range.lowerBound
        return Canvas { context, size in
            guard height > 0 else { return }
            for (index, kind) in kinds.enumerated() {
                let row = CGRect(x: 0, y: CGFloat(index) * height, width: size.width, height: height)
                if draftLines.contains(start + index) {
                    context.fill(Path(row), with: .color(.dsAccentSubtle))
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

/// The gutter text, redrawn only when its text changes (not on every hover).
private struct PullRequestDiffBlockGutter: View, Equatable {
    let text: PullRequestDiffBlockText
    let key: String

    var body: some View {
        Text(text.gutter)
            .fixedSize()
            .accessibilityHidden(true)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }
}

/// The code text, selectable, redrawn only when its text changes.
private struct PullRequestDiffBlockCode: View, Equatable {
    let text: PullRequestDiffBlockText
    let key: String

    var body: some View {
        if UserDefaults.standard.bool(forKey: "gitHubExperimentNoSelection") {
            Text(text.code)
                .fixedSize()
                .accessibilityRepresentation { Text(verbatim: text.plain) }
        } else {
            Text(text.code)
                .fixedSize()
                .textSelection(.enabled)
                .accessibilityRepresentation { Text(verbatim: text.plain) }
        }
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }
}
