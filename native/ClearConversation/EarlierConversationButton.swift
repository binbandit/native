import SwiftUI

/// The toolbar's way between a task's conversations: back to the one `/clear` set aside, or from a
/// set-aside one to the conversation that replaced it. Nothing shows for a task never cleared.
struct EarlierConversationButton: View {
    let session: SessionModel
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.earlierConversations.conversation(before: session.key) != nil {
            button("Earlier Conversation", systemImage: "clock.arrow.circlepath", to: .earlier)
                .help(
                    CommandRegistry.shared.help(
                        "Open the conversation before /clear", for: .sessionOpenEarlierConversation))
        } else if model.earlierConversations.conversation(after: session.key) != nil {
            button("Current Conversation", systemImage: "arrow.uturn.forward", to: .later)
                .help("This conversation was cleared with /clear. Open the one that replaced it.")
        }
    }

    private func button(
        _ title: String, systemImage: String, to direction: AppModel.ConversationDirection
    ) -> some View {
        Button {
            model.openConversation(direction, from: session.key)
        } label: {
            // A plain stack rather than a `Label`, which a toolbar would shorten to its title.
            HStack(spacing: DS.Space.sm) {
                Image(systemName: systemImage)
                Text(title)
            }
        }
        .buttonStyle(.header())
        .accessibilityLabel(title)
    }
}
