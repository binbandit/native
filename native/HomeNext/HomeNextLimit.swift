import ACP
import Foundation

/// An agent paused at its usage limit, as Home's one row for it and every task it stopped.
struct HomeNextLimit: Identifiable, Equatable {
    let agent: AgentDefinition.ID
    let agentName: String
    /// "5-hour", "weekly"; nil when the provider didn't say.
    var window: String?
    var resetsAt: Date?
    /// When the limit was reached: the row's age.
    let since: Date
    /// Tasks the limit stopped, by the sidebar's titles.
    var tasks: [SessionKey] = []
    var titles: [String] = []
    /// The user asked for the stopped tasks to resume at the reset.
    var resumes = false

    var id: AgentDefinition.ID { agent }

    /// "Claude Code paused until 3:05 PM"
    var title: String {
        guard let resetsAt else { return "\(agentName) reached its usage limit" }
        return "\(agentName) paused until \(resetsAt.formatted(date: .omitted, time: .shortened))"
    }

    /// "Its 5-hour limit. Regenerate the schema types resumes then."
    var detail: String {
        let limit = window.map { "Its \($0) limit." } ?? "Its usage limit."
        guard let first = titles.first else { return limit }
        let names = titles.count == 1 ? first : "\(first) and \(titles.count - 1) more"
        let verb = resumes && resetsAt != nil ? (titles.count == 1 ? "resumes then" : "resume then") : "stopped at it"
        return "\(limit) \(names) \(verb)."
    }
}
