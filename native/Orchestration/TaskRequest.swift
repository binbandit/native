import Foundation

/// A task one session hands another agent through `start_task`.
struct TaskRequest: Sendable {
    var agent: AgentDefinition.ID
    /// The session handing it over.
    var parent: SessionKey
    /// What the task's card says: the calling agent's title, or the start of the task.
    var title: String
    /// What the parent asked for, for the transcripts, which show who it's from on their own.
    var text: String
    /// What the task's agent is given: `text`, introduced with who it's for and how to reach them.
    var prompt: String
}
