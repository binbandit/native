import SwiftUI
import TextInput

/// A plain-message binding for hosts that do not need document tokens or caret completions.
struct DSMessageInput: View {
    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding
    var inputLabel = "Message"
    var maximumLines = 10
    var insets = DS.Composer.textInsets
    var fontSize = DS.TextInput.fontSize
    var lineSpacing = DS.TextInput.lineSpacing
    var onKey: (DSTextInputEvent) -> Bool
    @State private var document = TextInputDocument()

    var body: some View {
        DSTextInput(
            document: $document, placeholder: placeholder, maximumLines: maximumLines,
            fontSize: fontSize, lineSpacing: lineSpacing,
            accessibilityLabel: inputLabel,
            isFocused: Binding(get: { isFocused.wrappedValue }, set: { isFocused.wrappedValue = $0 }),
            onSubmit: { _ = onKey(.init(key: .return)) }, onEvent: onKey
        )
        // Hosts already reserve their own text margins; the native field includes a default inset.
        .padding(
            EdgeInsets(
                top: insets.top - DS.TextInput.inset, leading: insets.leading - DS.TextInput.inset,
                bottom: insets.bottom - DS.TextInput.inset, trailing: insets.trailing - DS.TextInput.inset)
        )
        .focused(isFocused)
        .onAppear(perform: synchronize)
        .onChange(of: text) { synchronize() }
        .onChange(of: document) { _, value in
            if text != value.plainText { text = value.plainText }
        }
    }

    private func synchronize() {
        if document.plainText != text { document = TextInputDocument(text) }
    }
}

#if DEBUG
private struct DSMessageInputPreview: View {
    @State var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        DSMessageInput(text: $text, placeholder: "Write a message", isFocused: $isFocused, onKey: { _ in false })
            .frame(width: DS.TextInput.previewWidth)
    }
}

#Preview("DSMessageInput - Empty and multiline") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            DSMessageInputPreview(text: "")
            DSMessageInputPreview(text: "Keep the draft.\nThen check the changed files.")
        }
    }
}
#endif
