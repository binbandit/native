import SwiftUI

enum ComposerFieldCompletion: Equatable {
    case file(String)
    case command(ComposerSlashCommand)
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
