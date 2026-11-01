#if DEBUG
import SwiftUI
#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif

/// Inert fixture states also available in the composer's gallery section.
struct DSTextInputGallery: View {
    @State private var document = TextInputDocument()
    var body: some View {
        DSTextInput(document: $document)
            .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsBorder) }
    }
}

private struct DSTextInputPreview: View {
    @State var document: TextInputDocument
    var width = DS.TextInput.previewWidth
    var maximumLines = 10
    var body: some View {
        DSTextInput(document: $document, maximumLines: maximumLines)
            .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsBorder) }
            .frame(width: width)
    }
}

#Preview("DSTextInput - Empty") {
    DSPreviewPair { DSTextInputPreview(document: .init()) }
}
#Preview("DSTextInput - One line") {
    DSPreviewPair { DSTextInputPreview(document: .init("Explain how the session reconnects.")) }
}
#Preview("DSTextInput - Mentions") {
    DSPreviewPair {
        DSTextInputPreview(
            document: .init(runs: [
                .text("Compare "), .mention(path: "Sources/Session.swift"), .text(" with "),
                .mention(path: "Tests/SessionTests.swift"), .text("\nand keep the public API unchanged."),
            ]))
    }
}
#Preview("DSTextInput - Wrapped and narrow") {
    DSPreviewPair {
        DSTextInputPreview(
            document: .init(
                "Keep the draft when a task reconnects.\n日本語の入力と絵文字 🧑🏽‍💻 also stay intact.\n\nThen add a regression test."),
            width: 240)
    }
}
#Preview("DSTextInput - Long mention") {
    DSPreviewPair {
        DSTextInputPreview(
            document: .init(runs: [
                .text("Review "), .mention(path: "Sources/AnExtremelyLongFileNameForTheSessionCoordinator.swift"),
            ]), width: 240)
    }
}
#Preview("DSTextInput - At scrolling cap") {
    DSPreviewPair {
        DSTextInputPreview(document: .init((1...14).map { "Line \($0): preserve the draft." }.joined(separator: "\n")))
    }
}
#Preview("DSTextInput - Trailing newline") {
    DSPreviewPair { DSTextInputPreview(document: .init("First line\n")) }
}
#endif
