import Foundation

extension WorkflowStep.Kind {
    /// What runs a step that isn't an agent's, where an agent's name would go.
    var runnerLabel: (title: String, systemImage: String)? {
        switch self {
        case .agent: nil
        case .pullRequest: ("GitHub", "arrow.triangle.pull")
        case .script: ("Script", "curlybraces")
        }
    }
}
