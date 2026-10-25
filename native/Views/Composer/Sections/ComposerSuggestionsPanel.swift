import ACP
import SwiftUI

/// The list floating above the composer for the suggestions being offered: slash commands or files.
struct ComposerSuggestionsPanel: View {
    let suggestions: ComposerSuggestions
    @Binding var highlighted: Int
    let changedFiles: Set<String>
    var referenceCounts: [String: FileReferenceProjection.Counts] = [:]
    let onChooseCommand: (ComposerSlashCommand) -> Void
    let onChooseFile: (String, FileMentionQuery) -> Void

    var body: some View {
        switch suggestions {
        case .commands(let commands):
            ComposerSuggestionList(items: commands, highlighted: $highlighted, onChoose: onChooseCommand) {
                command, isHighlighted in
                SlashCommandRow(command: command, isHighlighted: isHighlighted)
            }
        case .files(let files, let query):
            ComposerSuggestionList(items: files, highlighted: $highlighted, onChoose: { onChooseFile($0, query) }) {
                path, isHighlighted in
                FileMentionRow(
                    path: path, isChanged: changedFiles.contains(path), isHighlighted: isHighlighted,
                    counts: referenceCounts[path])
            }
        }
    }
}

#if DEBUG
#Preview("Suggestions panel") {
    let draft = "Tidy up @Sections/Que"
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSuggestionsPanel(
                suggestions: .commands(ComposerPreviewFixtures.commands), highlighted: .constant(0), changedFiles: [],
                onChooseCommand: { _ in }, onChooseFile: { _, _ in })
            if let query = FileMentionQuery(draft: draft, cursor: draft.endIndex) {
                ComposerSuggestionsPanel(
                    suggestions: .files(ComposerPreviewFixtures.files, query: query), highlighted: .constant(2),
                    changedFiles: [ComposerPreviewFixtures.files[2]], onChooseCommand: { _ in },
                    onChooseFile: { _, _ in })
            }
        }
        .frame(width: 560)
    }
}
#endif
