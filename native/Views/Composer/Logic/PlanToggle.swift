import ACP

/// Plan Mode, as one value of whichever setting holds it.
struct PlanToggle: Equatable {
    let setting: SelectSetting
    let plan: SelectSetting.Choice

    init?(_ setting: SelectSetting) {
        guard let plan = setting.choices.first(where: { $0.value == ComposerSettings.planValue }) else { return nil }
        self.setting = setting
        self.plan = plan
    }

    var isOn: Bool {
        setting.value == plan.value
    }
}
