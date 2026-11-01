import ACP
import SwiftUI
import TextInput

enum ComposerFieldCompletion: Equatable {
    case file(String)
    case command(ComposerSlashCommand)

    func inserting(
        in document: TextInputDocument, query: TextInputQuery
    ) -> (
        document: TextInputDocument, selection: NSRange, continues: Bool
    )? {
        var range = query.range
        let replacement: TextInputDocument
        var continues = false
        var caretAdjustment = 0
        switch self {
        case .file(let path):
            let display = document.displayText
            guard let indices = Range(query.range, in: display),
                let mention = FileMentionQuery(draft: display, cursor: indices.upperBound)
            else { return nil }
            range = NSRange(mention.range, in: display)
            continues = FileMention.isFolder(path)
            if continues {
                let text = FileMention.mention(of: path)
                replacement = TextInputDocument(text)
                caretAdjustment = text.hasSuffix("\"") ? 1 : 0
            } else {
                replacement = TextInputDocument(runs: [.mention(path: path), .text(" ")])
            }
        case .command(let command): replacement = TextInputDocument(command.invocation + " ")
        }
        guard let updated = document.replacing(range, with: replacement) else { return nil }
        return (
            updated,
            NSRange(location: range.location + replacement.displayText.utf16.count - caretAdjustment, length: 0),
            continues
        )
    }
}

struct ComposerFieldSuggestions: View {
    let items: [ComposerFieldCompletion]
    @Binding var highlighted: Int
    var choose: (ComposerFieldCompletion) -> Void

    var body: some View {
        ComposerSuggestionList(items: items, highlighted: $highlighted, onChoose: choose, isFloating: false) {
            item, selected in
            HStack(spacing: DS.Space.sm) {
                switch item {
                case .file(let path):
                    Image(systemName: path.hasSuffix("/") ? "folder" : "doc.text")
                        .foregroundStyle(.dsTextTertiary)
                    Text(path).lineLimit(1).truncationMode(.middle)
                case .command(let command):
                    Text(command.invocation).lineLimit(1)
                    Text(command.description).foregroundStyle(.dsTextTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.dsBody)
            .foregroundStyle(selected ? .dsTextPrimary : .dsTextSecondary)
        }
    }
}
