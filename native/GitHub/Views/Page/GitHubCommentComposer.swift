import SwiftUI

/// A Markdown comment box with a Write / Preview switch and the caller's buttons under it. Used
/// for conversation comments, line comments and replies, so they all behave the same.
struct GitHubCommentComposer<Actions: View>: View {
    @Binding var text: String
    let placeholder: String
    var isBusy = false
    /// Grabs focus when shown, for a comment the user just started.
    var focusesOnAppear = false
    let actions: Actions

    @State private var isPreviewing = false
    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>, placeholder: String, isBusy: Bool = false, focusesOnAppear: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        _text = text
        self.placeholder = placeholder
        self.isBusy = isBusy
        self.focusesOnAppear = focusesOnAppear
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
            .frame(minHeight: DS.Size.controlMD * 2.5, maxHeight: DS.Size.sidebarWidth)
            .fixedSize(horizontal: false, vertical: true)
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
    }
}
