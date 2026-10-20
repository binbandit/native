import CodeThemes
import GitHub
import SwiftUI

/// One block of a hunk in the Files Changed list: the fast drawing in platform text views, or line
/// by line with wrapping when the file wraps or a cut-off line in the block was opened. Text is
/// built once per block, colors, font and width, and cached on the page model.
struct PullRequestDiffBlockRow: View {
    let model: PullRequestPageModel
    let path: String
    let hunk: DiffHunk
    let range: Range<Int>
    /// Characters of code that fit beside the gutter.
    let columns: Int
    /// The width of one character of code.
    let characterWidth: CGFloat
    let isShiftDown: Bool

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsCodeThemes) private var codeThemes
    @Environment(\.dsCodeFont) private var codeFont

    var body: some View {
        let colors = DSCodeColors(environment, on: .surface)
        let numberWidth = model.numberWidth(path)
        if model.wrapsBlock(path, hunk, range) {
            PullRequestWrappedDiffBlock(
                model: model, path: path, hunk: hunk, range: range, numberWidth: numberWidth,
                highlighted: model.highlighted[PullRequestPageModel.hunkKey(path, hunk)], colors: colors,
                columns: columns, characterWidth: characterWidth)
        } else {
            let key = blockKey
            let metrics = Self.metrics(codeFont)
            PullRequestDiffBlock(
                model: model, path: path, hunk: hunk, range: range,
                text: blockText(key: key, colors: colors, numberWidth: numberWidth, metrics: metrics), textKey: key,
                isShiftDown: isShiftDown, lineHeight: metrics.lineHeight,
                gutterWidth: (CGFloat(PullRequestDiffBlockText.gutterColumns(numberWidth: numberWidth)) * characterWidth)
                    .rounded(.up))
        }
    }

    /// What decides the text: its lines, whether they're highlighted yet, the colors, the font and
    /// the width.
    private var blockKey: String {
        let highlighted = model.highlighted[PullRequestPageModel.hunkKey(path, hunk)] != nil
        return
            "\(path)#\(hunk.id)#\(range)#\(highlighted)#\(colorScheme)#\(codeThemes.hashValue)#\(codeFont.hashValue)#\(columns)"
    }

    private func blockText(
        key: String, colors: DSCodeColors, numberWidth: Int, metrics: PullRequestDiffBlockRowMetrics
    ) -> PullRequestDiffBlockText {
        if let cached = model.blockTexts[key] { return cached }
        let text = PullRequestDiffBlockText(
            lines: hunk.lines[range], highlighted: model.highlighted[PullRequestPageModel.hunkKey(path, hunk)],
            colors: colors, numberWidth: numberWidth, columns: columns, font: metrics.font,
            lineHeight: metrics.lineHeight, environment: environment)
        model.blockTexts[key] = text
        return text
    }

    /// The platform font and line height for a code font, worked out once: every block on screen
    /// asks for them.
    private static var metricsCache: [DSCodeFont: PullRequestDiffBlockRowMetrics] = [:]

    private static func metrics(_ codeFont: DSCodeFont) -> PullRequestDiffBlockRowMetrics {
        if let cached = metricsCache[codeFont] { return cached }
        let font = codeFont.platformFont(offset: DSCodeTextRole.compact.sizeOffset)
        let metrics = PullRequestDiffBlockRowMetrics(
            font: font, lineHeight: PlatformCodeText.lineHeight(font: font, spacing: codeFont.lineSpacing(.compact)))
        metricsCache[codeFont] = metrics
        return metrics
    }
}

private struct PullRequestDiffBlockRowMetrics {
    let font: DSPlatformFont
    let lineHeight: CGFloat
}

#if NATIVE_PREVIEWS_WIP
#Preview("Diff block rows") {
    DSPreviewPair {
        PullRequestPagePreview { model, _ in
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ForEach(model.rows.filter(\.isPreviewBlock).prefix(2)) { row in
                    PullRequestFilesRowView(model: model, row: row, width: 760, characterWidth: 7, isShiftDown: false)
                }
            }
            .codeTextStyle(.compact)
        }
        .frame(width: 760)
    }
}
#endif
