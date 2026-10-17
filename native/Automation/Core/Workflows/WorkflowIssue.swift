import Foundation

/// A mistake in a workflow definition. Definitions come from plugins' JSON, so they're checked
/// before they can run, and the picker shows why one can't.
nonisolated struct WorkflowIssue: Hashable, Sendable, CustomStringConvertible {
    /// The step it's about, or nil for the workflow as a whole.
    var step: String?
    var message: String

    var description: String {
        step.map { "Step \"\($0)\": \(message)" } ?? message
    }

    /// Every problem with `definition`; empty when it can run.
    static func find(in definition: WorkflowDefinition) -> [WorkflowIssue] {
        var issues: [WorkflowIssue] = []
        if definition.id.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(WorkflowIssue(message: "The workflow needs an id."))
        }
        if definition.steps.isEmpty {
            issues.append(WorkflowIssue(message: "The workflow has no steps."))
        }
        var earlier: Set<String> = []
        for step in definition.steps {
            issues += problems(with: step, in: definition, earlier: earlier)
            earlier.insert(step.id)
        }
        issues += sharedTaskConflicts(in: definition)
        return issues
    }

    private static func problems(with step: WorkflowStep, in definition: WorkflowDefinition, earlier: Set<String>) -> [WorkflowIssue] {
        var messages: [String] = []
        if step.id.range(of: #"^[A-Za-z][A-Za-z0-9_-]*$"#, options: .regularExpression) == nil {
            messages.append("ids start with a letter and use only letters, digits, - and _.")
        }
        if earlier.contains(step.id) {
            messages.append("another step already uses this id.")
        }
        // Steps refer back only, so the definition's order is always a valid run order.
        for dependency in definition.dependencies(of: step) where !earlier.contains(dependency) {
            messages.append("\"after\" names \"\(dependency)\", which isn't an earlier step.")
        }
        let ancestors = definition.ancestors(of: step)
        if let referenced = step.agent?.referencedStep, !earlier.contains(referenced) {
            messages.append("its agent refers to \"\(referenced)\", which isn't an earlier step.")
        }
        if let continued = step.continues {
            if !ancestors.contains(continued) {
                messages.append("it continues \"\(continued)\", which has to finish before it.")
            } else if definition.step(continued)?.kind != .agent {
                messages.append("it continues \"\(continued)\", which isn't an agent step.")
            }
        }
        var templates: [String] = []
        switch step.kind {
        case .agent:
            if step.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append("the prompt is empty.")
            }
            if step.pullRequest != nil {
                messages.append("\"pullRequest\" only applies to pull request steps.")
            }
            templates = [step.prompt]
        case .pullRequest:
            if let pullRequest = step.pullRequest {
                templates = [pullRequest.title, pullRequest.body]
            } else {
                messages.append("a pull request step needs \"pullRequest\" with at least a body.")
            }
            if step.goal != nil || step.agent != nil || step.continues != nil {
                messages.append("a pull request step doesn't run on an agent, so it takes no agent, continues or goal.")
            }
        }
        for variable in templates.flatMap(WorkflowTemplate.variables(in:)) {
            if case .unknown(let name) = variable {
                messages.append("{{\(name)}} isn't a variable.")
            } else if let referenced = variable.referencedStep, !ancestors.contains(referenced) {
                messages.append("it uses \"\(referenced)\"'s result, but doesn't wait for that step.")
            }
        }
        return messages.map { WorkflowIssue(step: step.id, message: $0.prefix(1).uppercased() + $0.dropFirst()) }
    }

    /// Two steps that continue the same task would prompt it at once; they have to run in order.
    private static func sharedTaskConflicts(in definition: WorkflowDefinition) -> [WorkflowIssue] {
        let continuing = definition.steps.filter { $0.continues != nil }
        var issues: [WorkflowIssue] = []
        for (index, step) in continuing.enumerated() {
            for other in continuing[(index + 1)...] where other.continues == step.continues {
                if !definition.ancestors(of: other).contains(step.id) {
                    issues.append(WorkflowIssue(step: other.id, message: "It continues the same task as \"\(step.id)\", so it has to wait for that step."))
                }
            }
        }
        return issues
    }
}
