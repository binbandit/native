import ACP
import Foundation

/// A task's mode, as Native remembers it: which mode, and the settings that mode changed with
/// what they were before, so leaving it puts them back.
public struct ModeSelection: Codable, Hashable, Sendable {
    /// By option id: the value before any mode changed it, and the value the mode set.
    public struct Restore: Codable, Hashable, Sendable {
        public var original: String
        public var applied: String
    }

    public var mode: Mode.ID
    public private(set) var restore: [String: Restore] = [:]

    public init(mode: Mode.ID = .build) {
        self.mode = mode
    }

    /// The changes that move a session on `options` into the mode `resolution` describes, and the
    /// selection afterwards. Settings the last mode changed and this one doesn't touch go back to
    /// what they were, unless someone changed them since; the model's change comes first, since it
    /// can change what the other settings offer.
    public func switching(
        to mode: Mode.ID, _ resolution: ModeResolution, options: [ConfigOption]
    ) -> (changes: [ModeResolution.Change], selection: ModeSelection) {
        var next = ModeSelection(mode: mode)
        var changes: [ModeResolution.Change] = []
        let touched = Set(resolution.changes.map(\.optionID))
        for (id, entry) in restore.sorted(by: { $0.key < $1.key }) where !touched.contains(id) {
            guard let option = options.first(where: { $0.id == id }),
                ModeAgentSettings.current(of: option) == entry.applied,
                ModeAgentSettings.choices(of: option).contains(where: { $0.value == entry.original })
            else { continue }
            changes.append(.init(optionID: id, value: entry.original))
        }
        for change in resolution.changes {
            guard let option = options.first(where: { $0.id == change.optionID }),
                let current = ModeAgentSettings.current(of: option)
            else { continue }
            // Still as the last mode left it: what came before that is what to go back to.
            var original = restore[change.optionID].flatMap { current == $0.applied ? $0.original : nil } ?? current
            if original == change.value, change.value == ModeAgentSettings.planValue {
                // Plan Mode was on already (the agent turned it on): leaving goes to the first level
                // that isn't it, and the plan mode stays this mode's to end.
                original = ModeAgentSettings.choices(of: option).first { $0.value != change.value }?.value ?? original
            }
            if original != change.value {
                next.restore[change.optionID] = Restore(original: original, applied: change.value)
            }
            if current != change.value {
                changes.append(change)
            }
        }
        let isModel = { (id: String) in options.first { $0.id == id }?.category == "model" }
        return (changes.filter { isModel($0.optionID) } + changes.filter { !isModel($0.optionID) }, next)
    }

    /// Carries the intent to another adapter without retaining that adapter's option IDs or
    /// restore values. A confirmed planning restriction belongs to the copied mode there too.
    public func continuing(
        options: [ConfigOption], allows: (ConfigOption, String) -> Bool = { _, _ in true }
    ) -> ModeSelection {
        var next = ModeSelection(mode: mode)
        let agent = ModeAgentSettings(options)
        if mode != .build, agent.isPlanOn, let plan = agent.plan {
            let offered = ModeAgentSettings.choices(of: plan)
                .filter { $0.value != ModeAgentSettings.planValue && allows(plan, $0.value) }.map(\.value)
            let original =
                AgentModelPermissions.selection(for: nil, offered: offered)?.value
                ?? ModeAgentSettings.planValue
            next.restore[plan.id] = Restore(original: original, applied: ModeAgentSettings.planValue)
        }
        return next
    }

    /// The mode in effect on a session with `options`. The agent's own plan mode can move under
    /// Native: when the agent leaves a plan mode this selection turned on (a plan was approved),
    /// the task is building again; when it turns plan mode on itself, the task is planning.
    public func effectiveMode(options: [ConfigOption]) -> Mode.ID {
        let agent = ModeAgentSettings(options)
        guard let plan = agent.plan else { return mode }
        let turnedOnHere = restore[plan.id]?.applied == ModeAgentSettings.planValue
        switch (agent.isPlanOn, turnedOnHere) {
        case (false, true): return .build
        case (true, false): return .plan
        default: return mode
        }
    }
}
