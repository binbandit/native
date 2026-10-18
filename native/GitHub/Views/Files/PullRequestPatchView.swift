import CodeThemes
import GitHub
import SwiftUI

/// A file's diff from its patch, hunk by hunk, with conversations under the lines they're on and
/// the new comment under the lines it's for. Clicking a line number starts a comment; shift-click
/// (or "Extend Comment to Here") widens it to a range, as on GitHub.
struct PullRequestPatchView: View {
    let model: PullRequestPageModel
    let path: String
    let hunks: [DiffHunk]

    @Environment(\.self) private var environment
    @State private var highlighted: [String: [[CodeSegment]]] = [:]
    @State private var isShiftDown = false
    @State private var showsAllLines = false

    var body: some View {
        let colors = DSCodeColors(environment, on: .surface)
        let threads = model.threads(in: path)
        let numberWidth = numberTemplate
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleHunks) { hunk in
                PullRequestHunkHeader(hunk: hunk)
                ForEach(hunk.lines.indices, id: \.self) { index in
                    let line = hunk.lines[index]
                    PullRequestDiffLineRow(
                        line: line,
                        text: highlighted[hunk.id].flatMap { $0.indices.contains(index) ? colors.text($0[index]) : nil },
                        numberTemplate: numberWidth,
                        isSelected: isInDraft(line),
                        model: model,
                        anchor: anchor(for: line, in: hunk),
                        extendAnchor: extended(to: line, in: hunk),
                        isShiftDown: isShiftDown
                    )
                    if let target = line.anchor {
                        ForEach(threads.filter { $0.anchor?.side == target.side && $0.anchor?.line == target.line }) { thread in
                            PullRequestReviewThreadView(model: model, thread: thread, showsAnchor: false)
                                .padding(DS.Space.md)
                        }
                        if let draft = model.draft, draft.anchor.path == path, draft.anchor.side == target.side,
                            draft.anchor.line == target.line
                        {
                            PullRequestCommentDraftView(model: model)
                                .padding(DS.Space.md)
                        }
                    }
                }
            }
            if lineCount > PullRequestFilesLayout.initialLineLimit, !showsAllLines {
                Button("Show All \(lineCount) Lines") { showsAllLines = true }
                    .buttonStyle(.ds(.secondary))
                    .padding(DS.Space.md)
            }
        }
        .codeTextStyle(.compact)
        .foregroundStyle(colors.isNative ? Color.dsTextPrimary : colors.color(.foreground))
        .trackingShift($isShiftDown)
        .task(id: path) { await highlight() }
    }

    private var lineCount: Int {
        hunks.reduce(0) { $0 + $1.lines.count }
    }

    /// Hunks up to the line limit, so a huge file doesn't stall the list; "Show All" lifts it.
    private var visibleHunks: [DiffHunk] {
        guard !showsAllLines else { return hunks }
        var count = 0
        return hunks.prefix { hunk in
            defer { count += hunk.lines.count }
            return count < PullRequestFilesLayout.initialLineLimit
        }
    }

    private var numberTemplate: String {
        let largest = hunks.flatMap(\.lines).compactMap { max($0.oldNumber ?? 0, $0.newNumber ?? 0) }.max() ?? 0
        return String(repeating: "8", count: max(String(largest).count, 2))
    }

    private func anchor(for line: DiffHunk.Line, in hunk: DiffHunk) -> ReviewAnchor? {
        line.anchor.map { ReviewAnchor(path: path, side: $0.side, line: $0.line) }
    }

    /// The draft widened to `line`, when that makes a valid range: same hunk, same side, later line.
    private func extended(to line: DiffHunk.Line, in hunk: DiffHunk) -> ReviewAnchor? {
        guard let draft = model.draft, draft.anchor.path == path, let target = line.anchor,
            target.side == draft.anchor.side, hunk.index(side: target.side, line: draft.anchor.line) != nil
        else { return nil }
        let start = min(draft.anchor.startLine ?? draft.anchor.line, target.line)
        let end = max(draft.anchor.line, target.line)
        guard start != end || draft.anchor.startLine != nil else { return nil }
        return ReviewAnchor(path: path, side: target.side, line: end, startLine: start, startSide: target.side)
    }

    private func isInDraft(_ line: DiffHunk.Line) -> Bool {
        guard let draft = model.draft, draft.anchor.path == path, let target = line.anchor,
            target.side == draft.anchor.side
        else { return false }
        return ((draft.anchor.startLine ?? draft.anchor.line)...draft.anchor.line).contains(target.line)
    }

    /// Highlights each hunk as one snippet, off the main thread; lines draw plain until then.
    private func highlight() async {
        guard let language = CodeLanguage.forPath(path) else { return }
        for hunk in hunks where highlighted[hunk.id] == nil {
            let code = hunk.lines.map { $0.kind == .noNewline ? "" : $0.text }.joined(separator: "\n")
            highlighted[hunk.id] = await CodeHighlightCache.shared.highlightLines(code, language: language)
        }
    }
}

/// `@@ -10,6 +10,7 @@ func run()`, between hunks.
private struct PullRequestHunkHeader: View {
    let hunk: DiffHunk

    var body: some View {
        Text("\(Text(hunk.header).foregroundStyle(.dsTextTertiary))\(Text(hunk.section.map { "  " + $0 } ?? "").foregroundStyle(.dsTextSecondary))")
            .font(.dsMonoCaption)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.dsHover)
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
