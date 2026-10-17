import Foundation

/// What an automation does when it runs. Each becomes a workflow run, so prompts and goals get the
/// same status, recovery and approval handling as workflows.
public nonisolated enum AutomationAction: Codable, Hashable, Sendable {
    case prompt(String)
    case goal(objective: String, budget: GoalBudget)
    /// A workflow from the library by id, with its input.
    case workflow(id: String, input: String)

    public var summary: String {
        switch self {
        case .prompt: "Prompt"
        case .goal(_, let budget): "Goal" + (budget.maxIterations.map { " · \($0) turns" } ?? "")
        case .workflow: "Workflow"
        }
    }

    /// The workflow and input a run starts, with what triggered it appended so the agent knows
    /// what to look at. Nil when the workflow is gone from the library.
    public func workflow(named name: String, library: WorkflowLibrary, context: String?) -> (definition: WorkflowDefinition, input: String)? {
        let suffix = context.map { "\n\nTriggered by: \($0)" } ?? ""
        switch self {
        case .prompt(let text):
            let step = WorkflowStep(id: "run", title: name, prompt: "{{input}}")
            return (WorkflowDefinition(id: "automation", name: name, summary: "", symbol: "clock.arrow.circlepath", steps: [step]), text + suffix)
        case .goal(let objective, let budget):
            let step = WorkflowStep(id: "run", title: name, prompt: "{{input}}", goal: budget)
            return (WorkflowDefinition(id: "automation", name: name, summary: "", symbol: "clock.arrow.circlepath", steps: [step]), objective + suffix)
        case .workflow(let id, let input):
            guard let definition = library.runnable.first(where: { $0.id == id }) else { return nil }
            return (definition, input + suffix)
        }
    }
}
