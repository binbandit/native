import ACP

/// A select-type session setting, unwrapped for display. Other kinds aren't shown.
struct SelectSetting: Equatable {
    typealias Choice = ConfigOption.SelectOption

    /// The value adapters use for "let the model decide" (Claude Code's effort), which isn't a level.
    static let defaultValue = "default"

    let option: ConfigOption
    let value: String
    let choices: [Choice]

    init?(_ option: ConfigOption) {
        guard case .select(let value, let choices) = option.kind else { return nil }
        self.option = option
        self.value = value
        // A gateway's long list can repeat a value; the value is a choice's identity.
        self.choices = choices.uniqued
    }

    var current: Choice? {
        choices.first { $0.value == value }
    }

    var currentName: String {
        current?.name ?? value
    }

    /// The choice after the current one among `choices`, wrapping around; the first when the current
    /// value isn't among them.
    func next(in choices: [Choice]) -> Choice? {
        guard !choices.isEmpty else { return nil }
        let index = choices.firstIndex { $0.value == value }.map { $0 + 1 } ?? 0
        return choices[index % choices.count]
    }

    /// A two-way setting the agent models as an "on"/"off" select, like Fast mode.
    var isSwitch: Bool {
        Set(choices.map(\.value)) == ["on", "off"]
    }

    var isOn: Bool {
        value == "on"
    }

    /// Levels least to most, without the model-default choice; for an effort setting.
    var levels: [Choice] {
        choices.filter { $0.value != Self.defaultValue }
    }

    /// How many level bars are lit; nil while the model picks its own level.
    var litLevel: Int? {
        levels.firstIndex { $0.value == value }.map { $0 + 1 }
    }
}
