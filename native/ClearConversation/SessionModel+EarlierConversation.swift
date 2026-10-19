extension SessionModel {
    /// Whether `/clear` set this conversation aside for a fresh one. It stays readable, but takes no
    /// new messages: those go to the conversation that replaced it.
    var isEarlierConversation: Bool {
        services.earlierConversations.isSetAside(key)
    }
}
