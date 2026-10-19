import SwiftUI

/// Where the composer sits, on a conversation `/clear` set aside: it's kept to read, and new
/// messages go to the conversation that replaced it, one click (or Session ▸ Open Current
/// Conversation) away.
struct EarlierConversationBar: View {
    let session: SessionModel
    @Environment(AppModel.self) private var model
    @Environment(\.transcriptColumnMaxWidth) private var columnWidth

    var body: some View {
        ComposerSurface(isFloating: true) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .accessibilityHidden(true)
                Text("The conversation before /clear, kept to read")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Current Conversation") {
                    model.openConversation(.later, from: session.key)
                }
                .buttonStyle(.ds(.secondary))
                .help(
                    CommandRegistry.shared.help(
                        "Open the conversation that replaced this one", for: .sessionOpenCurrentConversation))
            }
            .padding(.leading, DS.Composer.textInsets.leading)
            .padding(.trailing, DS.Composer.controlsInset)
            .padding(.vertical, DS.Composer.controlsInset)
        }
        .frame(maxWidth: columnWidth)
        .padding(.horizontal, DS.Space.xxl)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
