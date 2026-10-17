import Foundation

/// Every workflow the user can run: Native's own, then those enabled plugins contribute. A broken
/// definition stays listed with its issues instead of taking its plugin down with it.
nonisolated struct WorkflowLibrary: Hashable, Sendable {
    struct Entry: Hashable, Sendable, Identifiable {
        enum Source: Hashable, Sendable {
            case builtIn
            /// The contributing plugin's id.
            case plugin(String)
        }

        let definition: WorkflowDefinition
        let source: Source
        let issues: [WorkflowIssue]

        var id: String {
            definition.id
        }

        var isRunnable: Bool {
            issues.isEmpty
        }
    }

    private(set) var entries: [Entry]

    /// `contributions` are plugins' workflows by plugin id, in plugin order.
    init(builtIns: [WorkflowDefinition] = BuiltInWorkflows.all, contributions: [(plugin: String, workflows: [WorkflowDefinition])] = []) {
        var entries: [Entry] = []
        var ids: Set<String> = []
        let sources = builtIns.map { ($0, Entry.Source.builtIn) }
            + contributions.flatMap { contribution in contribution.workflows.map { ($0, Entry.Source.plugin(contribution.plugin)) } }
        for (definition, source) in sources {
            var issues = WorkflowIssue.find(in: definition)
            // The first one keeps the id, so a plugin can't replace a built-in or another plugin's.
            if !ids.insert(definition.id).inserted {
                issues.insert(WorkflowIssue(message: "Another workflow already uses the id \"\(definition.id)\"."), at: 0)
            }
            entries.append(Entry(definition: definition, source: source, issues: issues))
        }
        self.entries = entries
    }

    var runnable: [WorkflowDefinition] {
        entries.filter(\.isRunnable).map(\.definition)
    }

    func entry(_ id: String) -> Entry? {
        entries.first { $0.id == id }
    }
}
