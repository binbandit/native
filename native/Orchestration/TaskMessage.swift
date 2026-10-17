import Foundation

/// A message one session sends another through `send_message`.
struct TaskMessage: Sendable {
    enum Delivery: String, Sendable {
        /// Added to the recipient's running turn.
        case steered
        /// Held until the recipient's running turn ends, then sent as its next prompt.
        case queued
        /// Sent as a prompt to the idle recipient, starting a turn.
        case prompted
    }

    var sender: SessionKey
    var recipient: SessionKey
    /// What the sender wrote, for the transcripts, which show who it's from on their own.
    var text: String
    /// What the recipient's agent is given: `text`, introduced with who sent it and how to reply,
    /// since an agent's prompt carries nothing else to say so.
    var prompt: String
}
