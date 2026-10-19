import SwiftUI

/// An answer in the app's Markdown, with what can be done with it: "Draft Comment from This" puts
/// the whole answer in the pull request's comment box, and each paragraph, list or code block's
/// menu drafts just that part. Neither posts anything.
struct PullRequestAskAnswer: View {
    let text: String
    /// Done streaming, so its actions show.
    let isFinished: Bool
    let draftComment: (String) -> Void

    var body: some View {
        let sections = text.markdownSections
        VStack(alignment: .leading, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections.indices, id: \.self) { index in
                    let part = String(sections[index])
                    MarkdownSectionView(source: part, isFirst: index == 0)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            if isFinished { menu(for: part) }
                        }
                }
            }
            if isFinished {
                HStack(spacing: DS.Space.sm) {
                    Button("Draft Comment from This", systemImage: "text.bubble") { draftComment(text) }
                        .buttonStyle(.ds(.secondary))
                        .help("Puts this answer in the pull request's comment box to edit. Nothing is posted.")
                    IconButton("Copy Answer", systemImage: "doc.on.doc") { DSPasteboard.copy(text) }
                }
            }
        }
    }

    @ViewBuilder private func menu(for part: String) -> some View {
        Button("Draft Comment from This Part", systemImage: "text.bubble") { draftComment(part) }
        Button("Draft Comment from Whole Answer", systemImage: "text.bubble") { draftComment(text) }
        Divider()
        Button("Copy This Part", systemImage: "doc.on.doc") { DSPasteboard.copy(part) }
        Button("Copy Answer", systemImage: "doc.on.doc") { DSPasteboard.copy(text) }
    }
}
