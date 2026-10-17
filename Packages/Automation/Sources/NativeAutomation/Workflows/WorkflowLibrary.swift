import Foundation

/// Every workflow the user can run: Native's own, then those enabled plugins contribute. A broken
/// definition stays listed with its issues instead of taking its plugin down with it.
public nonisolated struct WorkflowLibrary: Hashable, Sendable {
    public struct Entry: Hashable, Sendable, Identifiable {
        public enum Source: Hashable, Sendable {
            case builtIn
            /// The contributing plugin's id.
            case plugin(String)
        }

        public let definition: WorkflowDefinition
        public let source: Source
        public let issues: [WorkflowIssue]

        public var id: String {
            definition.id
        }

        public var isRunnable: Bool {
            issues.isEmpty
        }
    }

    public private(set) var entries: [Entry]

    /// `contributions` are plugins' workflows by plugin id, in plugin order.
    public init(builtIns: [WorkflowDefinition] = BuiltInWorkflows.all, contributions: [(plugin: String, workflows: [WorkflowDefinition])] = []) {
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

    public var runnable: [WorkflowDefinition] {
        entries.filter(\.isRunnable).map(\.definition)
    }

    public func entry(_ id: String) -> Entry? {
        entries.first { $0.id == id }
    }
}
