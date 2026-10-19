import ACP
import Foundation

/// The settings of one agent's session that a mode can change, read from its ACP config options
/// by category: the permission mode (`mode`), Plan Mode (a `collaboration_mode` with a `plan`
/// choice, else the permission mode's own `plan` choice), the model and the effort.
public struct ModeAgentSettings: Hashable, Sendable {
    /// The value agents use for Plan Mode.
    public static let planValue = "plan"

    public struct Choice: Hashable, Sendable {
        public var value: String
        public var name: String
    }

    /// The permission mode.
    public private(set) var autonomy: ConfigOption?
    /// Its levels from least to most autonomous, without Plan Mode.
    public private(set) var levels: [Choice] = []
    /// The setting that holds Plan Mode, and whether it's the permission mode itself (it suspends
    /// the autonomy level while it's on).
    public private(set) var plan: ConfigOption?
    public private(set) var model: ConfigOption?
    public private(set) var effort: ConfigOption?

    public init(_ options: [ConfigOption]) {
        var collaboration: ConfigOption?
        for option in options {
            guard case .select(_, let choices) = option.kind else { continue }
            switch option.category {
            case "mode" where autonomy == nil:
                autonomy = option
                levels = choices.filter { $0.value != Self.planValue }.map { Choice(value: $0.value, name: $0.name) }
            case "collaboration_mode"
            where collaboration == nil && choices.contains(where: { $0.value == Self.planValue }):
                collaboration = option
            case "model" where model == nil:
                model = option
            case "thought_level" where effort == nil:
                effort = option
            default:
                continue
            }
        }
        let autonomyHasPlan = autonomy.map { Self.choices(of: $0).contains { $0.value == Self.planValue } } ?? false
        plan = collaboration ?? (autonomyHasPlan ? autonomy : nil)
    }

    /// Whether Plan Mode is the permission mode's own value, standing in for the autonomy level.
    public var isPlanInAutonomy: Bool {
        plan != nil && plan?.id == autonomy?.id
    }

    public var isPlanOn: Bool {
        plan.map { Self.current(of: $0) == Self.planValue } ?? false
    }

    static func current(of option: ConfigOption) -> String? {
        if case .select(let current, _) = option.kind { current } else { nil }
    }

    static func choices(of option: ConfigOption) -> [ConfigOption.SelectOption] {
        if case .select(_, let choices) = option.kind { choices } else { [] }
    }

    /// The choice of `option` that `wanted` names, by value or by name, ignoring case.
    static func choice(in option: ConfigOption, matching wanted: String) -> ConfigOption.SelectOption? {
        let wanted = wanted.lowercased()
        let choices = choices(of: option)
        return choices.first { $0.value.lowercased() == wanted } ?? choices.first { $0.name.lowercased() == wanted }
    }
}
