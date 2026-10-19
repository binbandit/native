import ACP

/// What a mode does on one agent: the settings to change, and what it can't do there, in plain
/// words. Organization policy always wins: a forbidden level gives way to the nearest allowed one.
public struct ModeResolution: Hashable, Sendable {
    public struct Change: Hashable, Sendable {
        public var optionID: String
        public var value: String

        public init(optionID: String, value: String) {
            self.optionID = optionID
            self.value = value
        }
    }

    public internal(set) var changes: [Change] = []
    public internal(set) var limits: [ModeLimit] = []
    /// Whether the agent's own plan mode carries the mode (Plan, or read-only on an agent whose
    /// plan mode is its only read-only one).
    public internal(set) var usesAgentPlanMode = false

    /// Limits that mean the mode can't keep the agent from changing things.
    public var isReadOnlyUnenforced: Bool {
        limits.contains { limit in
            switch limit {
            case .readOnlyAsks, .readOnlyUnenforced: true
            default: false
            }
        }
    }
}

/// Something a mode can't do as asked on an agent, and what it does instead.
public enum ModeLimit: Hashable, Sendable {
    /// No plan mode, so Plan keeps the agent read-only and asks for a plan.
    case noPlanMode
    /// No read-only level, so the agent's plan mode (which changes nothing) stands in.
    case readOnlyViaPlanMode
    /// No read-only level: the least autonomous one, which asks before changes, stands in.
    case readOnlyAsks(level: String)
    /// No permission modes at all: being read-only rests on the instructions.
    case readOnlyUnenforced
    /// The agent has no level like the one asked for, so the nearest is used.
    case autonomyApproximated(wanted: ModeAutonomy, using: String)
    /// The agent has no permission modes, so the level asked for can't be set.
    case noAutonomy(wanted: ModeAutonomy)
    /// The organization doesn't allow the level, so the nearest allowed one is used.
    case forbidden(wanted: String, using: String?)
    case modelUnavailable(String)
    case effortUnavailable(String)

    /// The limit in a sentence, for the picker and Settings.
    public func text(agent: String, mode: String) -> String {
        switch self {
        case .noPlanMode:
            "\(agent) has no plan mode, so \(mode) keeps it read-only and asks for a plan first."
        case .readOnlyViaPlanMode:
            "\(agent) has no read-only mode, so \(mode) uses its plan mode, which can't change anything."
        case .readOnlyAsks(let level):
            "\(agent) has no read-only mode. At \(level) it asks before changing anything, so turn down what \(mode) shouldn't do."
        case .readOnlyUnenforced:
            "\(agent) has no permission modes, so Native can't stop it from changing things: \(mode) relies on its instructions."
        case .autonomyApproximated(let wanted, let using):
            "\(agent) has no \(wanted.title) level, so \(mode) uses \(using)."
        case .noAutonomy(let wanted):
            "\(agent) has no permission modes, so \(mode) can't set \(wanted.title)."
        case .forbidden(let wanted, let using?):
            "Your organization doesn't allow \(wanted), so \(mode) uses \(using)."
        case .forbidden(let wanted, nil):
            "Your organization doesn't allow \(wanted), so \(mode) keeps the task's level."
        case .modelUnavailable(let model):
            "\(agent) doesn't offer \(model), so \(mode) keeps the task's model."
        case .effortUnavailable(let effort):
            "\(agent) doesn't offer \(effort) effort, so \(mode) keeps the task's effort."
        }
    }

    /// Whether it's the organization's doing, said once when the mode is picked rather than only
    /// shown in the picker.
    public var isPolicy: Bool {
        if case .forbidden = self { true } else { false }
    }
}

/// Works out what a mode changes on an agent's session (`ModeResolution`).
public enum ModeResolver {
    /// `allows` says whether policy permits a value of an option (`PolicyPermissionModes`).
    public static func resolve(
        _ mode: Mode, options: [ConfigOption], allows: (ConfigOption, String) -> Bool = { _, _ in true }
    ) -> ModeResolution {
        let agent = ModeAgentSettings(options)
        var resolution = ModeResolution()
        let settings = mode.settings
        // The model first: changing it can change the efforts on offer.
        if let model = settings.model {
            if let option = agent.model, let choice = ModeAgentSettings.choice(in: option, matching: model) {
                resolution.changes.append(.init(optionID: option.id, value: choice.value))
            } else {
                resolution.limits.append(.modelUnavailable(model))
            }
        }
        if let effort = settings.effort {
            if let option = agent.effort, let choice = ModeAgentSettings.choice(in: option, matching: effort) {
                resolution.changes.append(.init(optionID: option.id, value: choice.value))
            } else {
                resolution.limits.append(.effortUnavailable(effort))
            }
        }
        var autonomy = settings.autonomy
        if settings.usesPlanMode {
            if let plan = agent.plan, allows(plan, ModeAgentSettings.planValue) {
                resolution.changes.append(.init(optionID: plan.id, value: ModeAgentSettings.planValue))
                resolution.usesAgentPlanMode = true
            } else {
                resolution.limits.append(agent.plan == nil ? .noPlanMode : .forbidden(wanted: "Plan Mode", using: nil))
                autonomy = .readOnly
            }
        }
        // Plan Mode in the permission mode already holds it; a separate one leaves it to set.
        if let autonomy, !(resolution.usesAgentPlanMode && agent.isPlanInAutonomy) {
            resolveAutonomy(autonomy, agent: agent, allows: allows, into: &resolution)
        }
        return resolution
    }

    private static func resolveAutonomy(
        _ wanted: ModeAutonomy, agent: ModeAgentSettings, allows: (ConfigOption, String) -> Bool,
        into resolution: inout ModeResolution
    ) {
        guard let option = agent.autonomy, !agent.levels.isEmpty else {
            resolution.limits.append(wanted == .readOnly ? .readOnlyUnenforced : .noAutonomy(wanted: wanted))
            return
        }
        let ranked = agent.levels.enumerated().compactMap { index, choice in
            rank(of: choice, at: index, of: agent.levels.count).map { (choice: choice, rank: $0) }
        }
        let allowed = ranked.filter { allows(option, $0.choice.value) }
        func set(_ choice: ModeAgentSettings.Choice) {
            resolution.changes.append(.init(optionID: option.id, value: choice.value))
        }
        if wanted == .readOnly {
            if let readOnly = allowed.first(where: { $0.rank == .readOnly }) {
                return set(readOnly.choice)
            }
            let forbiddenReadOnly = ranked.first { $0.rank == .readOnly }
            if agent.isPlanInAutonomy, let plan = agent.plan, allows(plan, ModeAgentSettings.planValue) {
                resolution.changes.append(.init(optionID: plan.id, value: ModeAgentSettings.planValue))
                resolution.usesAgentPlanMode = true
                resolution.limits.append(
                    forbiddenReadOnly.map { .forbidden(wanted: $0.choice.name, using: "Plan Mode") }
                        ?? .readOnlyViaPlanMode)
                return
            }
            guard let least = allowed.first else {
                resolution.limits.append(.readOnlyUnenforced)
                return
            }
            set(least.choice)
            resolution.limits.append(
                forbiddenReadOnly.map { .forbidden(wanted: $0.choice.name, using: least.choice.name) }
                    ?? .readOnlyAsks(level: least.choice.name))
            return
        }
        let target = nearest(to: wanted, in: ranked)
        guard let target else {
            resolution.limits.append(.noAutonomy(wanted: wanted))
            return
        }
        if allows(option, target.choice.value) {
            set(target.choice)
            if target.rank != wanted {
                resolution.limits.append(.autonomyApproximated(wanted: wanted, using: target.choice.name))
            }
        } else if let fallback = nearest(to: target.rank, in: allowed) {
            set(fallback.choice)
            resolution.limits.append(.forbidden(wanted: target.choice.name, using: fallback.choice.name))
        } else {
            resolution.limits.append(.forbidden(wanted: target.choice.name, using: nil))
        }
    }

    /// The level closest to `wanted` on the autonomy scale; between two as close, the more careful.
    private static func nearest(
        to wanted: ModeAutonomy, in levels: [(choice: ModeAgentSettings.Choice, rank: ModeAutonomy)]
    ) -> (choice: ModeAgentSettings.Choice, rank: ModeAutonomy)? {
        let scale = ModeAutonomy.allCases
        guard let target = scale.firstIndex(of: wanted) else { return nil }
        return levels.min { lhs, rhs in
            let left = abs((scale.firstIndex(of: lhs.rank) ?? 0) - target)
            let right = abs((scale.firstIndex(of: rhs.rank) ?? 0) - target)
            return left == right ? (scale.firstIndex(of: lhs.rank) ?? 0) < (scale.firstIndex(of: rhs.rank) ?? 0) : left < right
        }
    }

    /// Where an agent's level sits on the scale: by the bundled adapters' values (never by agent),
    /// then by a read-only name, then by its place in the agent's own order. Nil for a level that
    /// fits nowhere, which is never picked.
    static func rank(of choice: ModeAgentSettings.Choice, at index: Int, of count: Int) -> ModeAutonomy? {
        guard !unranked.contains(choice.value) else { return nil }
        if let known = known[choice.value] {
            return known
        }
        if [choice.value, choice.name].contains(where: { $0.lowercased().filter(\.isLetter) == "readonly" }) {
            return .readOnly
        }
        if index == 0 { return .ask }
        if count > 2, index == count - 1 { return .full }
        return index * 2 < count ? .edit : .auto
    }

    private static let known: [String: ModeAutonomy] = [
        // codex-acp
        "read-only": .readOnly,
        "workspace-write": .edit,
        "agent": .auto,
        "agent-full-access": .full,
        // claude-agent-acp
        "default": .ask,
        "acceptEdits": .edit,
        "auto": .auto,
        "bypassPermissions": .full,
    ]

    /// claude-agent-acp's `dontAsk` never asks, but refuses whatever isn't already allowed: it's
    /// no step on the scale.
    private static let unranked: Set<String> = ["dontAsk"]
}
