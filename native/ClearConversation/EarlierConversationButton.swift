import SwiftUI

/// The toolbar's way back to the conversation `/clear` set aside. A set-aside conversation shows the
/// way forward where its composer would be (`EarlierConversationBar`), so nothing shows here then,
/// nor for a task never cleared.
struct EarlierConversationButton: View {
    let session: SessionModel
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.earlierConversations.conversation(before: session.key) != nil {
            Button {
                model.openConversation(.earlier, from: session.key)
            } label: {
                // A plain stack rather than a `Label`, which a toolbar would shorten to its title.
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Earlier Conversation")
                }
            }
            .buttonStyle(.header())
            .accessibilityLabel("Earlier Conversation")
            .help(
                CommandRegistry.shared.help("Open the conversation before /clear", for: .sessionOpenEarlierConversation)
            )
        }
    }
}
