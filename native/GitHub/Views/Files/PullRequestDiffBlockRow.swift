import CodeThemes
import GitHub
import SwiftUI

/// One block of a hunk in the Files Changed list: the fast one-text-per-block drawing, or line by
/// line with wrapping when the file wraps or a cut-off line in the block was opened. Text is built
/// once per block, colors and width, and cached on the page model.
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

    var body: some View {
        content
            // Diffs read better without ligatures, and shaping them is a large share of laying out
            // a block. The user's choice still applies to code everywhere else.
            .codeTextStyle(.compact)
            .transformEnvironment(\.dsCodeFont) {
                if !UserDefaults.standard.bool(forKey: "gitHubExperimentLigatures") { $0.ligatures = false }
            }
    }

    @ViewBuilder private var content: some View {
        let colors = DSCodeColors(environment, on: .surface)
        let numberWidth = model.numberWidth(path)
        if model.wrapsBlock(path, hunk, range) {
            PullRequestWrappedDiffBlock(
                model: model, path: path, hunk: hunk, range: range, numberWidth: numberWidth,
                highlighted: model.highlighted[PullRequestPageModel.hunkKey(path, hunk)], colors: colors,
                columns: columns, characterWidth: characterWidth)
        } else {
            let key = blockKey
            PullRequestDiffBlock(
                model: model, path: path, hunk: hunk, range: range,
                text: blockText(key: key, colors: colors, numberWidth: numberWidth), textKey: key,
                isShiftDown: isShiftDown, markerOffset: CGFloat(max(columns - 3, 0)) * characterWidth)
        }
    }

    /// What decides the text: its lines, whether they're highlighted yet, the colors and the width.
    private var blockKey: String {
        let highlighted = model.highlighted[PullRequestPageModel.hunkKey(path, hunk)] != nil
        return "\(path)#\(hunk.id)#\(range)#\(highlighted)#\(colorScheme)#\(codeThemes.hashValue)#\(columns)"
    }

    private func blockText(key: String, colors: DSCodeColors, numberWidth: Int) -> PullRequestDiffBlockText {
        if let cached = model.blockTexts[key] { return cached }
        let text = PullRequestDiffBlockText(
            lines: hunk.lines[range], highlighted: model.highlighted[PullRequestPageModel.hunkKey(path, hunk)],
            colors: colors, numberWidth: numberWidth, columns: columns)
        model.blockTexts[key] = text
        return text
    }
}
