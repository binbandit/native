import ACP

/// The session settings the composer's controls show, picked out by their ACP category and read the
/// way the reference app presents its own: a model with an effort meter, an autonomy meter, and Plan Mode.
/// Every method answers which setting to change to what; the view applies it.
struct ComposerSettings: Equatable {
    struct Change: Equatable {
        let setting: SelectSetting
        let value: String
    }

    static let planValue = "plan"

    var model: SelectSetting?
    var effort: SelectSetting?
    /// On/off switches that tune the model, such as Fast mode; shown in the model picker.
    var modelSwitches: [SelectSetting] = []
    /// The permission mode, shown as the autonomy meter.
    var autonomy: SelectSetting?
    var plan: PlanToggle?
    /// Settings no dedicated control covers, shown as plain menus.
    var others: [SelectSetting] = []

    init(_ options: [ConfigOption]) {
        var collaboration: SelectSetting?
        for option in options {
            guard let setting = SelectSetting(option) else { continue }
            switch option.category {
            case "model" where model == nil:
                model = setting
            case "thought_level" where effort == nil:
                effort = setting
            case "model_config" where setting.isSwitch:
                modelSwitches.append(setting)
            case "mode" where autonomy == nil:
                autonomy = setting
            case "collaboration_mode" where collaboration == nil && PlanToggle(setting) != nil:
                collaboration = setting
            default:
                others.append(setting)
            }
        }
        // Codex keeps Plan Mode in a setting of its own; Claude Code makes it a permission mode.
        plan = (collaboration ?? autonomy).flatMap(PlanToggle.init)
    }

    /// Permission modes from least to most autonomous (for Claude Code: Manual, Accept edits, Auto,
    /// Bypass permissions), without Plan Mode.
    var autonomyLevels: [SelectSetting.Choice] {
        autonomy?.choices.filter { $0.value != Self.planValue } ?? []
    }

    /// Whether Plan Mode has taken the permission mode's place, suspending the autonomy level.
    var isAutonomySuspended: Bool {
        autonomy?.value == Self.planValue
    }

    /// The autonomy level to show: the current one, or while Plan Mode suspends it, `resumed`.
    func shownAutonomyLevel(resumed: String?) -> Int {
        let value = isAutonomySuspended ? resumed : autonomy?.value
        return autonomyLevels.firstIndex { $0.value == value } ?? 0
    }

    var nextEffort: Change? {
        guard let effort, let next = effort.next(in: effort.choices) else { return nil }
        return Change(setting: effort, value: next.value)
    }

    var nextAutonomy: Change? {
        guard let autonomy, !isAutonomySuspended else { return nil }
        // Cycling skips the levels the organization forbids.
        let allowed = autonomyLevels.filter { !PolicyPermissionModes.forbids(autonomy.option, value: $0.value) }
        guard let next = autonomy.next(in: allowed) else { return nil }
        return Change(setting: autonomy, value: next.value)
    }

    /// Turns Plan Mode on, or off again. Leaving it as a permission mode restores `resumedAutonomy`,
    /// the level from before it started.
    func togglingPlan(resumedAutonomy: String?) -> Change? {
        guard let plan else { return nil }
        guard plan.isOn else { return Change(setting: plan.setting, value: plan.plan.value) }
        let levels = plan.setting.option.id == autonomy?.option.id
            ? autonomyLevels
            : plan.setting.choices.filter { $0.value != plan.plan.value }
        let off = levels.first { $0.value == resumedAutonomy } ?? levels.first
        return off.map { Change(setting: plan.setting, value: $0.value) }
    }
}
