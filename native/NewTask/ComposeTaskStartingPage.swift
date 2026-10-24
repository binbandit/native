import ACP
import SwiftUI

/// Frame two already uses the transcript's message renderer and final column width.
struct ComposeTaskStartingPage: View {
    let model: AppModel
    let compose: ComposeTaskModel
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let message {
                    MessageView(message: message)
                        .font(.dsCallout)
                        .frame(maxWidth: columnWidth.maxWidth)
                        .padding(.horizontal, DS.Space.xxl)
                        .padding(.top, DS.Space.xl)
                        .offset(y: isSettled || reduceMotion ? 0 : DS.ComposeTask.messageOffset)
                        .frame(maxWidth: .infinity)
                }
            }
            if let editor = compose.editor {
                ComposerSurface(isFloating: true) {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        Text("Starting \(editor.agentName)…")
                            .font(.dsCallout).foregroundStyle(.dsTextTertiary)
                        HStack {
                            Text(compose.starting?.stepLabel ?? "Preparing the task").font(.dsCaption)
                                .foregroundStyle(.dsTextSecondary)
                            Spacer()
                            Button("Cancel Start") {
                                model.cancelComposeStart()
                            }.buttonStyle(.ds(.ghost))
                                .disabled(compose.starting?.openedSession != nil)
                        }
                    }.padding(DS.Space.lg)
                }
                .frame(maxWidth: columnWidth.maxWidth)
                .padding(.horizontal, DS.Space.xxl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xl)
                .offset(y: isSettled || reduceMotion ? 0 : DS.ComposeTask.composerOffset)
                .opacity(isSettled ? 1 : DS.ComposeTask.settlingOpacity)
            }
        }
        .onAppear {
            #if DEBUG
            if compose.previewState == "message" { return }
            #endif
            withAnimation(reduceMotion ? nil : DS.ComposeTask.settle) { isSettled = true }
        }
    }

    private var message: TranscriptMessage? {
        guard let editor = compose.editor else { return nil }
        var state = SessionState()
        state.appendUserMessage(
            editor.draft,
            attachments: MessageAttachment.shown(editor.attachments, capabilities: editor.promptCapabilities))
        guard case .message(let message) = state.items.first else { return nil }
        return message
    }
}

#if DEBUG
#Preview("Compose - Start fold") { ComposeTaskPreviewFixture(state: "folding") }
#Preview("Compose - First message") { ComposeTaskPreviewFixture(state: "message") }
#Preview("Compose - Settled") { ComposeTaskPreviewFixture(state: "settled") }
#endif
