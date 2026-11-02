import ACP

/// The agent's own Plan Mode, as one value of whichever setting holds it: a setting of its own, or
/// a permission mode that suspends the autonomy level while it's on. The Plan mode (native/Modes)
/// turns it on; the composer reads it so the setting isn't also shown as a plain menu.
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
