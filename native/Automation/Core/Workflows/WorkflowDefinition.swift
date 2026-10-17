import Foundation

/// A reusable multi-agent workflow: what it asks for and the steps it runs. Plain JSON, so plugins
/// contribute workflows in `plugin.json` (`"workflows": [...]`) and built-ins use the same format.
nonisolated struct WorkflowDefinition: Hashable, Sendable, Identifiable {
    /// Unique across built-ins and plugins.
    var id: String
    var name: String
    /// One sentence for the picker.
    var summary: String
    /// An SF Symbol.
    var symbol: String
    var input: WorkflowInput
    var steps: [WorkflowStep]

    init(id: String, name: String, summary: String, symbol: String = "point.3.connected.trianglepath.dotted", input: WorkflowInput = WorkflowInput(), steps: [WorkflowStep]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.input = input
        self.steps = steps
    }

    func step(_ id: String) -> WorkflowStep? {
        steps.first { $0.id == id }
    }

    /// The steps `step` waits for directly: its `after`, or the step before it.
    func dependencies(of step: WorkflowStep) -> [String] {
        if let after = step.after {
            return after
        }
        guard let index = steps.firstIndex(where: { $0.id == step.id }), index > 0 else { return [] }
        return [steps[index - 1].id]
    }

    /// Every step `step` waits for, directly or not.
    func ancestors(of step: WorkflowStep) -> Set<String> {
        var found: Set<String> = []
        var pending = dependencies(of: step)
        while let next = pending.popLast() {
            guard found.insert(next).inserted, let dependency = self.step(next) else { continue }
            pending += dependencies(of: dependency)
        }
        return found
    }
}

extension WorkflowDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, summary, symbol, input, steps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "point.3.connected.trianglepath.dotted"
        input = try container.decodeIfPresent(WorkflowInput.self, forKey: .input) ?? WorkflowInput()
        steps = try container.decode([WorkflowStep].self, forKey: .steps)
    }
}
