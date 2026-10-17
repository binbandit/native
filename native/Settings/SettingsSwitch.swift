import SwiftUI

/// the reference app's switch: a 40x20 track filled with the foreground when on, and a thumb that slides
/// across in 150ms. The label is for accessibility; the row shows the title.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(SettingsSwitchStyle())
    }
}

private struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        // A button, so the switch takes keyboard focus and toggles with Space.
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.dsTextPrimary : Color.dsBorder)
                .frame(width: SettingsMetrics.switchSize.width, height: SettingsMetrics.switchSize.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.dsSurface)
                        .frame(width: SettingsMetrics.switchThumb, height: SettingsMetrics.switchThumb)
                        .dsShadow(.drag)
                        .padding(DS.Space.xxs)
                }
                .animation(.dsStandard, value: configuration.isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(.focusEffect, Capsule())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
