import CodeThemes
import GitHub
import SwiftUI

/// A file's diff, hunk by hunk. Each hunk draws as a few text blocks rather than a view per line,
/// split only where a conversation or the comment being written sits under a line. Lines draw
/// plain first and pick up highlighting when it arrives from the background.
struct PullRequestPatchView: View {
    let model: PullRequestPageModel
    let path: String
    let hunks: [DiffHunk]

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsCodeThemes) private var codeThemes
    @State private var isShiftDown = false
    @State private var showsAllLines = false

    var body: some View {
        let colors = DSCodeColors(environment, on: .surface)
        let threads = model.threads(in: path)
        let numberWidth = self.numberWidth
        // Not lazy: the file list around it is, and a lazy stack nested in another leaves blocks
        // undrawn. Files show at most a few hundred lines here, in blocks of a few dozen.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleHunks, id: \.hunk.id) { hunk, shown in
                PullRequestHunkHeader(hunk: hunk)
                ForEach(segments(of: hunk, shown: shown, threads: threads), id: \.lowerBound) { segment in
                    let key = blockKey(hunk, segment)
                    PullRequestDiffBlock(
                        model: model, path: path, hunk: hunk, range: segment,
                        text: blockText(hunk, segment, key: key, colors: colors, numberWidth: numberWidth),
                        textKey: key, isShiftDown: isShiftDown)
                    if let last = segment.last {
                        attachments(after: hunk.lines[last], threads: threads)
                    }
                }
            }
            if lineCount > PullRequestFilesLayout.initialLineLimit, !showsEverything {
                Button("Show All \(lineCount) Lines") { showsAllLines = true }
                    .buttonStyle(.ds(.secondary))
                    .padding(DS.Space.md)
            }
        }
        .codeTextStyle(.compact)
        .foregroundStyle(colors.isNative ? Color.dsTextPrimary : colors.color(.foreground))
        .trackingShift($isShiftDown)
        .task(id: path) { await model.highlight(path) }
    }

    /// Conversations under the line, then the new comment if it's for this line.
    @ViewBuilder private func attachments(after line: DiffHunk.Line, threads: [ReviewThread]) -> some View {
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

    static let blockLines = 48

    /// The shown lines cut after every line that has something under it, and into short blocks.
    private func segments(of hunk: DiffHunk, shown: Range<Int>, threads: [ReviewThread]) -> [Range<Int>] {
        let anchored = Set(threads.compactMap(\.anchor).map { "\($0.side.rawValue)\($0.line)" })
        let draft = model.draft.flatMap { $0.anchor.path == path ? "\($0.anchor.side.rawValue)\($0.anchor.line)" : nil }
        var segments: [Range<Int>] = []
        var start = shown.lowerBound
        for index in shown {
            let key = hunk.lines[index].anchor.map { "\($0.side.rawValue)\($0.line)" }
            // Blocks stay short, so scrolling lays out a little at a time, never a whole long hunk.
            let isFull = index + 1 - start >= Self.blockLines
            if isFull || key.map({ anchored.contains($0) || $0 == draft }) == true {
                segments.append(start..<(index + 1))
                start = index + 1
            }
        }
        if start < shown.upperBound { segments.append(start..<shown.upperBound) }
        return segments
    }

    /// What decides a block's text: its lines, whether they're highlighted yet, and the colors.
    private func blockKey(_ hunk: DiffHunk, _ segment: Range<Int>) -> String {
        let highlighted = model.highlighted[PullRequestPageModel.hunkKey(path, hunk)] != nil
        return "\(path)#\(hunk.id)#\(segment)#\(highlighted)#\(colorScheme)#\(codeThemes.hashValue)"
    }

    private func blockText(
        _ hunk: DiffHunk, _ segment: Range<Int>, key: String, colors: DSCodeColors, numberWidth: Int
    ) -> PullRequestDiffBlockText {
        if let cached = model.blockTexts[key] { return cached }
        let text = PullRequestDiffBlockText(
            lines: hunk.lines[segment], highlighted: model.highlighted[PullRequestPageModel.hunkKey(path, hunk)],
            colors: colors, numberWidth: numberWidth)
        model.blockTexts[key] = text
        return text
    }

    /// Files with conversations show whole, so no comment hides behind "Show All".
    private var showsEverything: Bool {
        showsAllLines || !model.threads(in: path).isEmpty
    }

    private var lineCount: Int {
        hunks.reduce(0) { $0 + $1.lines.count }
    }

    /// Hunks and the lines of each to draw, up to the line limit; "Show All" lifts it.
    private var visibleHunks: [(hunk: DiffHunk, lines: Range<Int>)] {
        var budget = showsEverything ? Int.max : PullRequestFilesLayout.initialLineLimit
        var visible: [(hunk: DiffHunk, lines: Range<Int>)] = []
        for hunk in hunks where budget > 0 {
            let count = min(hunk.lines.count, budget)
            visible.append((hunk, 0..<count))
            budget -= count
        }
        return visible
    }

    private var numberWidth: Int {
        let largest = hunks.flatMap(\.lines).compactMap { max($0.oldNumber ?? 0, $0.newNumber ?? 0) }.max() ?? 0
        return max(String(largest).count, 2)
    }
}

/// `@@ -10,6 +10,7 @@ func run()`, between hunks.
private struct PullRequestHunkHeader: View {
    let hunk: DiffHunk

    var body: some View {
        Text(
            "\(Text(hunk.header).foregroundStyle(.dsTextTertiary))\(Text(hunk.section.map { "  " + $0 } ?? "").foregroundStyle(.dsTextSecondary))"
        )
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
