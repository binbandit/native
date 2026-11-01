/// An adapter owns its model identities. Group before filtering or deduplicating so equal values
/// from different agents never collide, and changing agents changes the entire model scope.
public struct AgentModelGroups<Agent: Hashable & Sendable, Model: Sendable>: Sendable {
    public struct Group: Sendable, Identifiable {
        public let id: Agent
        public var models: [Model]
    }

    public let groups: [Group]

    public init(_ models: [Model], agent: KeyPath<Model, Agent>) {
        var groups: [Group] = []
        var positions: [Agent: Int] = [:]
        for model in models {
            let id = model[keyPath: agent]
            if let index = positions[id] {
                groups[index].models.append(model)
            } else {
                positions[id] = groups.count
                groups.append(Group(id: id, models: [model]))
            }
        }
        self.groups = groups
    }

    public func models(for agent: Agent) -> [Model] {
        groups.first { $0.id == agent }?.models ?? []
    }
}
