import SwiftUI

/// The list floating above the composer for the suggestions being offered: slash commands or files.
struct ComposerSuggestionsPanel: View {
    let suggestions: ComposerSuggestions
    @Binding var highlighted: Int
    let changedFiles: Set<String>
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
                FileMentionRow(path: path, isChanged: changedFiles.contains(path), isHighlighted: isHighlighted)
            }
        }
    }
}
