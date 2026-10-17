import SwiftUI

/// A command for the user to run in their own terminal, in a sunken mono well with a copy button.
/// Native shows it and never runs it. Same look as GitHub's `CommandSnippet`, but as wide as its
/// container, since install commands run long.
struct AgentSetupCommand: View {
    let command: String

    @State private var didCopy = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.md) {
            Text("$")
                .foregroundStyle(.dsTextTertiary)
            Text(command)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(command)
            Spacer(minLength: DS.Space.md)
            IconButton(didCopy ? "Copied" : "Copy Command", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                DSPasteboard.copy(command)
                didCopy = true
            }
        }
        .font(.dsMono)
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(command)
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
