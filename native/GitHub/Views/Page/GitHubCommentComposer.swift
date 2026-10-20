import SwiftUI

/// A Markdown comment box with a Write / Preview switch and the caller's buttons under it. Used
/// for conversation comments, line comments and replies, so they all behave the same.
struct GitHubCommentComposer<Actions: View>: View {
    @Binding var text: String
    let placeholder: String
    var isBusy = false
    /// Grabs focus when shown, for a comment the user just started.
    var focusesOnAppear = false
    /// Grabs focus each time this changes, for text put in from elsewhere.
    var focusRequest = 0
    let actions: Actions

    @State private var isPreviewing = false
    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>, placeholder: String, isBusy: Bool = false, focusesOnAppear: Bool = false,
        focusRequest: Int = 0, @ViewBuilder actions: () -> Actions
    ) {
        _text = text
        self.placeholder = placeholder
        self.isBusy = isBusy
        self.focusesOnAppear = focusesOnAppear
        self.focusRequest = focusRequest
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Group {
                if isPreviewing {
                    ScrollView {
                        PullRequestMarkdownBody(source: text.isEmpty ? "Nothing to preview." : text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                } else {
                    TextEditor(text: $text)
                        .font(.dsCallout)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .font(.dsCallout)
                                    .foregroundStyle(.dsTextTertiary)
                                    .padding(.leading, CreatePullRequestLayout.editorTextInset)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.sm)
                }
            }
            // A fixed height: a text view in a scrolling page has no natural one.
            .frame(height: DS.Size.controlMD * 3)
            .background(.dsSurface, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .strokeBorder(isFocused ? Color.dsAccent : Color.dsBorder, lineWidth: 1)
            }
            HStack(spacing: DS.Space.sm) {
                Button(isPreviewing ? "Write" : "Preview") { isPreviewing.toggle() }
                    .buttonStyle(.ds(.ghost))
                    .disabled(isBusy)
                Spacer(minLength: DS.Space.md)
                actions
                    .disabled(isBusy)
            }
        }
        .onAppear { if focusesOnAppear { isFocused = true } }
        .onChange(of: focusRequest) {
            isPreviewing = false
            isFocused = true
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Comment composer") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            GitHubCommentComposerPreview(text: "")
            GitHubCommentComposerPreview(
                text: "Pushed a fix for the non-steering case.\n\n- Send Now stops the turn first\n- Then sends",
                isBusy: true)
        }
        .frame(width: PullRequestsLayout.contentWidth)
    }
}

/// Holds the composer's text, which it takes as a binding.
private struct GitHubCommentComposerPreview: View {
    @State var text: String
    var isBusy = false

    var body: some View {
        GitHubCommentComposer(text: $text, placeholder: "Leave a comment. Markdown works.", isBusy: isBusy) {
            Button(isBusy ? "Commenting…" : "Comment") {}
                .buttonStyle(.ds(.primary))
                .disabled(text.isEmpty)
        }
    }
}
#endif
