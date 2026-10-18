import Foundation

/// One skill however many places have it: Claude's, Codex's and the shared `.agents` folder can
/// all hold (or link to) the same skill, and the list shows it once with every place.
public struct SkillItem: Hashable, Sendable, Identifiable {
    public var id: String { key }
    /// What switches are stored under: the name, lowercased, as agents match names.
    public var key: String
    public var name: String
    public var description: String?
    /// Every place it is, the most specific scope first.
    public var places: [SkillFolder]
    /// What's wrong with any copy, and names one agent finds more than once.
    public var problems: [SkillProblem]
    /// The agents that load it: every agent reading a place where it's valid.
    public var agents: Set<SkillAgentFormat>

    public var primary: SkillFolder {
        // `SkillInventory` never makes an item without places.
        places[0]
    }

    public var hasErrors: Bool {
        problems.contains { $0.severity == .error }
    }

    /// Where it lives, deduplicated: "Project", "User", a plugin's name.
    public var scopes: [SkillScope] {
        places.map(\.root.scope).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Whether any copy is one Native can update or remove (the agents manage the others).
    public var isUserManaged: Bool {
        places.contains { $0.root.scope.isUserManaged }
    }

    /// Distinct folders, so a link and its target count once.
    public var distinctFolders: [SkillFolder] {
        places.reduce(into: []) { result, place in
            if !result.contains(where: { $0.resolvedPath == place.resolvedPath }) { result.append(place) }
        }
    }

    public static func key(for name: String) -> String {
        name.lowercased()
    }
}

public enum SkillInventory {
    /// Groups folders into skills by name, sorted by name.
    public static func items(_ folders: [SkillFolder]) -> [SkillItem] {
        Dictionary(grouping: folders) { SkillItem.key(for: $0.name) }
            .map { key, folders in item(key: key, folders: folders) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func item(key: String, folders: [SkillFolder]) -> SkillItem {
        let places = folders.sorted { ($0.root.scope.rank, $0.path) < ($1.root.scope.rank, $1.path) }
        let primary = places.first { $0.document != nil } ?? places[0]
        var problems: [SkillProblem] = places.flatMap(\.problems).reduce(into: []) {
            if !$0.contains($1) { $0.append($1) }
        }
        let allAgents = places.reduce(into: Set<SkillAgentFormat>()) { $0.formUnion($1.root.agents) }
        for agent in SkillAgentFormat.allCases where allAgents.contains(agent) {
            let visible = places.filter { $0.root.agents.contains(agent) && $0.digest != nil }
            var byDigest: [String: SkillFolder] = [:]
            for place in visible where byDigest[place.digest ?? ""] == nil { byDigest[place.digest ?? ""] = place }
            if byDigest.count > 1 {
                problems.append(.duplicate(agent: agent, paths: byDigest.values.map(\.path).sorted()))
            }
        }
        let loading = places.filter { !$0.problems.contains { $0.severity == .error } }
        return SkillItem(
            key: key,
            name: primary.name,
            description: primary.document?.frontmatter.description,
            places: places,
            problems: problems,
            agents: loading.reduce(into: []) { $0.formUnion($1.root.agents) }
        )
    }
}
