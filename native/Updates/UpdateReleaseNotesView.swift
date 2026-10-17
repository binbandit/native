import SwiftUI

/// Release notes as scripts/release drafts them from conventional commits: "## Section" headings
/// and "- item" lines, with inline Markdown (code, links) inside. Long notes scroll.
struct UpdateReleaseNotesView: View {
    let markdown: String

    private enum Line: Hashable {
        case heading(String)
        case item(String)
        case text(String)
    }

    private var lines: [Line] {
        markdown.split(separator: "\n", omittingEmptySubsequences: true).map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                return .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return .item(String(line.dropFirst(2)))
            }
            return .text(line)
        }
    }

    var body: some View {
        CappedHeightScrollView(maxHeight: 220) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    switch line {
                    case .heading(let text):
                        Text(text)
                            .font(.dsCaptionMedium)
                            .foregroundStyle(.dsTextSecondary)
                            .padding(.top, index == 0 ? 0 : DS.Space.sm)
                    case .item(let text):
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                            Text("•").foregroundStyle(.dsTextTertiary)
                            inline(text)
                        }
                    case .text(let text):
                        inline(text)
                    }
                }
            }
            .font(.dsBody)
            .foregroundStyle(.dsTextPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.md)
        .background(.dsSurfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
        .accessibilityLabel("Release notes")
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
    }
}
