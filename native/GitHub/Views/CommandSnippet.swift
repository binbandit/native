import SwiftUI

/// A shell command to run, in a sunken mono well with a copy button.
struct CommandSnippet: View {
    let command: String
    let onCopy: () -> Void

    @State private var didCopy = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.md) {
            Text("$")
                .foregroundStyle(.dsTextTertiary)
            Text(command)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
            Spacer(minLength: DS.Space.lg)
            IconButton(didCopy ? "Copied" : "Copy Command", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                onCopy()
                didCopy = true
            }
        }
        .font(.dsMono)
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xs)
        .frame(width: DS.Size.sidebarWidth + DS.Space.xxxl)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
