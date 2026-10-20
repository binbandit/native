import SwiftUI

/// A switch: a 40x20 track filled with the foreground when on, and a thumb that slides
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
        SettingsSwitchBody(configuration: configuration)
    }
}

private struct SettingsSwitchBody: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // A button, so the switch takes keyboard focus and toggles with Space.
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.dsTextPrimary : Color.dsSwitchOff)
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
                // Half strength while disabled: a switch that can't change looks it, whichever way
                // it's set.
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(SettingsSwitchButtonStyle())
        .settingsFocusShape(Capsule())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// No pressed or disabled styling of its own: the switch draws both.
private struct SettingsSwitchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#if DEBUG
#Preview("Switch") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            SettingsSwitch("On", isOn: .constant(true))
            SettingsSwitch("Off", isOn: .constant(false))
            SettingsSwitch("On, disabled", isOn: .constant(true))
                .disabled(true)
            SettingsSwitch("Off, disabled", isOn: .constant(false))
                .disabled(true)
        }
    }
}
#endif
