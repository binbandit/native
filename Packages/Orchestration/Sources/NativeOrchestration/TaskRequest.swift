import Foundation

/// A task one session hands another agent through `start_task`.
public struct TaskRequest: Sendable {
    /// The id the task will go by, chosen before it starts.
    public var id: String
    public var agent: TaskAgent
    /// The session handing it over.
    public var parent: TaskSessionRef
    public var parentAgentName: String
    /// What the task's card says: the calling agent's title, or the start of the task.
    public var title: String
    /// What the parent asked for, for the transcripts, which show who it's from on their own.
    public var text: String
    /// What the task's agent is given: `text`, introduced with who it's for and how to reach them.
    public var prompt: String

    public init(
        id: String, agent: TaskAgent, parent: TaskSessionRef, parentAgentName: String, title: String, text: String,
        prompt: String
    ) {
        self.id = id
        self.agent = agent
        self.parent = parent
        self.parentAgentName = parentAgentName
        self.title = title
        self.text = text
        self.prompt = prompt
    }
}

/// A message one session sends another through `send_message`.
public struct TaskMessage: Sendable {
    public enum Delivery: String, Sendable {
        /// Added to the recipient's running turn.
        case steered
        /// Held until the recipient's running turn ends, then sent as its next prompt.
        case queued
        /// Sent as a prompt to the idle recipient, starting a turn.
        case prompted
    }

    public var sender: TaskSessionRef
    public var recipient: TaskSessionRef
    /// What the sender wrote, for the transcripts, which show who it's from on their own.
    public var text: String
    /// What the recipient's agent is given: `text`, introduced with who sent it and how to reply,
    /// since an agent's prompt carries nothing else to say so.
    public var prompt: String

    public init(sender: TaskSessionRef, recipient: TaskSessionRef, text: String, prompt: String) {
        self.sender = sender
        self.recipient = recipient
        self.text = text
        self.prompt = prompt
    }
}
