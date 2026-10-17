import Foundation

/// A task one session hands another agent through `start_task`.
struct TaskRequest: Sendable {
    var agent: AgentDefinition.ID
    /// The session handing it over, by client id.
    var parent: UUID
    /// The calling agent's suggestion; nil leaves titling to the app.
    var title: String?
    /// What the parent asked for, for the transcripts, which show who it's from on their own.
    var text: String
    /// What the task's agent is given: `text`, introduced with who it's for and how to reach them.
    var prompt: String
}
