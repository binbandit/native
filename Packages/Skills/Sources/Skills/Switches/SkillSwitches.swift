import Foundation

/// Native's on/off switch for every skill, for all projects and per project, by name so one
/// switch covers every agent and every copy. A skill without a switch is on; a project's switch
/// beats the global one. Switches never touch a skill's files: they turn into each agent's own
/// session or launch settings (`SkillOffList`).
public struct SkillSwitches: Hashable, Sendable, Codable {
    public enum Mode: String, Hashable, Sendable, Codable {
        case on
        case off
    }

    /// By `SkillItem.key`.
    public private(set) var global: [String: Mode]
    /// By project path (`SkillPaths.key`), then skill key.
    public private(set) var projects: [String: [String: Mode]]

    public init(global: [String: Mode] = [:], projects: [String: [String: Mode]] = [:]) {
        self.global = global
        self.projects = projects
    }

    /// The mode in `directory`: the switch of the innermost project containing it, else the
    /// global one, else on.
    public func mode(of skill: String, in directory: URL?) -> Mode {
        if let directory, let project = project(containing: directory), let mode = projects[project]?[skill] {
            return mode
        }
        return global[skill] ?? .on
    }

    /// The switch set exactly at `project` (or globally when nil), without falling back.
    public func explicitMode(of skill: String, in project: URL?) -> Mode? {
        guard let project else { return global[skill] }
        return projects[SkillPaths.key(project)]?[skill]
    }

    /// Sets a switch; nil removes it, so the skill follows the global switch (or is on).
    public mutating func set(_ mode: Mode?, for skill: String, in project: URL?) {
        guard let project else {
            global[skill] = mode
            return
        }
        let path = SkillPaths.key(project)
        projects[path, default: [:]][skill] = mode
        if projects[path]?.isEmpty == true { projects[path] = nil }
    }

    /// Projects that set `skill` differently from the global switch.
    public func projectOverrides(for skill: String) -> [String: Mode] {
        projects.compactMapValues { $0[skill] }.filter { $0.value != (global[skill] ?? .on) }
    }

    private func project(containing directory: URL) -> String? {
        let path = SkillPaths.key(directory)
        return projects.keys.filter { SkillPaths.path(path, isInside: $0) }.max { $0.count < $1.count }
    }
}

/// What to leave out of a session or an agent process, in both forms agents switch by.
public struct SkillOffList: Hashable, Sendable {
    /// Skill names, for agents that switch by name (Claude Code).
    public var names: [String] = []
    /// SKILL.md paths of every copy, as listed and with links resolved, for agents that switch by
    /// file (Codex).
    public var skillFiles: [String] = []

    public init(names: [String] = [], skillFiles: [String] = []) {
        self.names = names
        self.skillFiles = skillFiles
    }

    public var isEmpty: Bool {
        names.isEmpty && skillFiles.isEmpty
    }
}

extension SkillSwitches {
    /// What's off for a session working in `directory`.
    public func offList(for items: [SkillItem], in directory: URL?) -> SkillOffList {
        offList(items.filter { mode(of: $0.key, in: directory) == .off }.map { ($0, $0.places) })
    }

    /// What an agent switching per process can leave out, since one process serves every
    /// project: skills off everywhere, plus project copies turned off in their own project (their
    /// files are only there, so leaving them out doesn't reach other projects).
    public func processOffList(for items: [SkillItem]) -> SkillOffList {
        offList(
            items.compactMap { item in
                let places = item.places.filter { place in
                    mode(of: item.key, in: place.root.scope.project) == .off
                }
                return places.isEmpty ? nil : (item, places)
            })
    }

    private func offList(_ off: [(item: SkillItem, places: [SkillFolder])]) -> SkillOffList {
        var list = SkillOffList()
        for (item, places) in off.sorted(by: { $0.item.key < $1.item.key }) {
            if !list.names.contains(item.name) { list.names.append(item.name) }
            for place in places {
                for file in [place.skillFile, SkillPaths.join(place.resolvedPath, "SKILL.md")]
                where !list.skillFiles.contains(file) {
                    list.skillFiles.append(file)
                }
            }
        }
        return list
    }

    /// Why a switch on `item` doesn't fully reach some agent, in words for the row: agents that
    /// can't leave skills out, plugin skills, and agents that can't do it per project.
    public func limitations(of item: SkillItem, agents: [SkillAgentFormat]) -> [String] {
        let isOffInAProjectOnly =
            global[item.key] != .off && projects.values.contains { $0[item.key] == .off }
        return agents.filter(item.agents.contains).compactMap { agent in
            let places = item.places.filter { $0.root.agents.contains(agent) }
            switch agent.switching {
            case .unsupported:
                return "\(agent.displayName) can't leave a skill out of a session, so it still loads it."
            case .perSession:
                guard places.contains(where: { !agent.canSwitch($0.root.scope) }) else { return nil }
                return "\(agent.displayName) can't hide skills from its plugins; turn the plugin off in \(agent.displayName)."
            case .perProcess:
                let reachesEveryCopy = places.allSatisfy { $0.root.scope.project != nil }
                guard isOffInAProjectOnly, !reachesEveryCopy else { return nil }
                return "\(agent.displayName) can only turn it off in every project, so it still loads it here."
            }
        }
    }
}
