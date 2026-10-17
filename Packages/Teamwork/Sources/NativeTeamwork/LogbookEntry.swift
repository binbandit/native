import Foundation

/// One line in the expedition's logbook: what happened, when, and to which part of it.
public nonisolated struct LogbookEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        /// Ordinary progress: something started or finished.
        case progress
        /// Something passed or completed.
        case success
        /// Something stopped short or needs the user.
        case attention
        /// The user did something.
        case user
    }

    public let id: UUID
    public let at: Date
    public let kind: Kind
    public let text: String
    /// What it's about, so the overview can link to it.
    public let slot: CrewSlot?

    public init(at: Date, kind: Kind, text: String, slot: CrewSlot? = nil) {
        id = UUID()
        self.at = at
        self.kind = kind
        self.text = text
        self.slot = slot
    }
}
