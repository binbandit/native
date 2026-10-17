import Foundation

/// One step of a workflow: an agent task (or a pull request) with a prompt template, the steps it
/// waits for, and optionally an approval gate before it runs and a goal loop while it does.
nonisolated struct WorkflowStep: Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Hashable, Sendable {
        /// Runs `prompt` as a task on an agent.
        case agent
        /// Opens a pull request through the host (the GitHub feature) from `pullRequest`.
        case pullRequest
    }

    /// Referenced by other steps (`{{steps.<id>.output}}`, `after`, `sameAs`...).
    var id: String
    var title: String
    var kind: Kind
    /// Nil runs the step on the run's default agent. Ignored when `continues` is set.
    var agent: WorkflowAgentChoice?
    /// Runs the step in an earlier step's task instead of a fresh one, so the agent keeps that
    /// step's context, e.g. the implementer addressing review feedback on its own changes.
    var continues: String?
    /// The task's prompt, a `WorkflowTemplate`. For a goal step, the objective.
    var prompt: String
    /// The steps that must finish first. Nil means the step before it; `[]` starts it right away,
    /// in parallel with whatever else can run.
    var after: [String]?
    /// Asks the user before the step runs.
    var approval: WorkflowApproval?
    /// Runs the step as a goal loop with this budget, instead of a single turn.
    var goal: GoalBudget?
    var pullRequest: WorkflowPullRequestTemplate?

    init(
        id: String, title: String, kind: Kind = .agent, agent: WorkflowAgentChoice? = nil, continues: String? = nil,
        prompt: String = "", after: [String]? = nil, approval: WorkflowApproval? = nil, goal: GoalBudget? = nil,
        pullRequest: WorkflowPullRequestTemplate? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.agent = agent
        self.continues = continues
        self.prompt = prompt
        self.after = after
        self.approval = approval
        self.goal = goal
        self.pullRequest = pullRequest
    }

    /// `"goal": true` asks for a goal loop without saying how long; ten turns is enough for most
    /// steps and keeps an unattended workflow from running away.
    static let defaultGoalBudget = GoalBudget(maxIterations: 10)
}

extension WorkflowStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, agent, continues, prompt, after, approval, goal, pullRequest
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? id
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .agent
        agent = try container.decodeIfPresent(WorkflowAgentChoice.self, forKey: .agent)
        continues = try container.decodeIfPresent(String.self, forKey: .continues)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        after = try container.decodeIfPresent([String].self, forKey: .after)
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .approval) {
            approval = flag ? WorkflowApproval() : nil
        } else {
            approval = try container.decodeIfPresent(WorkflowApproval.self, forKey: .approval)
        }
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .goal) {
            goal = flag ? Self.defaultGoalBudget : nil
        } else {
            goal = try container.decodeIfPresent(GoalBudget.self, forKey: .goal)
        }
        pullRequest = try container.decodeIfPresent(WorkflowPullRequestTemplate.self, forKey: .pullRequest)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        if kind != .agent {
            try container.encode(kind, forKey: .kind)
        }
        try container.encodeIfPresent(agent, forKey: .agent)
        try container.encodeIfPresent(continues, forKey: .continues)
        if !prompt.isEmpty {
            try container.encode(prompt, forKey: .prompt)
        }
        try container.encodeIfPresent(after, forKey: .after)
        try container.encodeIfPresent(approval, forKey: .approval)
        try container.encodeIfPresent(goal, forKey: .goal)
        try container.encodeIfPresent(pullRequest, forKey: .pullRequest)
    }
}
