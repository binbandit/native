import SwiftUI

/// The composer's text field: 13pt text that grows with the draft to a cap, then scrolls. Keys go
/// to `onKey` first, so the composer can send, recall and drive its lists.
struct ComposerEditor: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let onKey: (KeyPress) -> KeyPress.Result

    var body: some View {
        // TextEditor doesn't size to its content, so a hidden copy of the text sets the height and the
        // editor fills it, scrolling once the cap is reached.
        Text(verbatim: text.hasSuffix("\n") || text.isEmpty ? text + " " : text)
            .font(.dsCallout)
            .lineSpacing(ComposerMetrics.editorLineSpacing)
            .padding(.horizontal, ComposerMetrics.editorLineFragmentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: ComposerMetrics.editorMaxHeight, alignment: .top)
            // Size to the text (capped) rather than to whatever height is on offer.
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay {
                TextEditor(text: $text)
                    .font(.dsCallout)
                    .lineSpacing(ComposerMetrics.editorLineSpacing)
                    .foregroundStyle(.dsTextPrimary)
                    .textEditorStyle(.plain)
                    .scrollIndicators(.never)
                    .focused(isFocused)
                    .onKeyPress(phases: [.down, .repeat], action: onKey)
                    .accessibilityLabel("Message")
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.leading, ComposerMetrics.editorLineFragmentPadding)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Composer.textInsets.leading - ComposerMetrics.editorLineFragmentPadding)
            .padding(.vertical, DS.Composer.textInsets.top)
    }
}
