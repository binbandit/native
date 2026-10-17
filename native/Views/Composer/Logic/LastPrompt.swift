import ACP

extension SessionState {
    /// The text of the last prompt the user sent, for ↑ in an empty composer.
    var lastPrompt: String? {
        items.reversed().lazy.compactMap { item -> String? in
            guard case .message(let message) = item, message.role == .user else { return nil }
            return message.text
        }.first
    }
}
