import GitHub
import SwiftUI

/// A comment body: Markdown, with GitHub's suggested changes drawn as the lines they'd become.
struct PullRequestMarkdownBody: View {
    let source: String
    /// The commented lines as they read now, to show what a suggestion replaces.
    var original: String?

    var body: some View {
        let segments = SuggestionBlock.segments(of: GitHubMarkdown.displayed(source))
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(segments.indices, id: \.self) { index in
                switch segments[index] {
                case .markdown(let text):
                    MarkdownView(text)
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextPrimary)
                case .suggestion(let replacement):
                    PullRequestSuggestionView(original: original, replacement: replacement)
                }
            }
        }
    }
}

/// "Suggested change": the lines it removes and the lines it adds.
private struct PullRequestSuggestionView: View {
    let original: String?
    let replacement: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text("Suggested change")
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
            SeparatorLine()
            VStack(alignment: .leading, spacing: 0) {
                if let original, !original.isEmpty {
                    lines(original, kind: .removed)
                }
                lines(replacement, kind: .added)
            }
            .padding(.vertical, DS.Space.xs)
        }
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .clipShape(shape)
    }

    private func lines(_ text: String, kind: DiffHunk.Line.Kind) -> some View {
        ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) {
            _, line in
            HStack(spacing: DS.Space.sm) {
                Text(kind == .removed ? "-" : "+")
                    .foregroundStyle(kind == .removed ? .dsDanger : .dsSuccess)
                Text(verbatim: line.isEmpty ? " " : String(line))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .codeTextStyle(.compact)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 1)
            .background((kind == .removed ? Color.dsDanger : Color.dsSuccess).opacity(0.12))
        }
    }
}
