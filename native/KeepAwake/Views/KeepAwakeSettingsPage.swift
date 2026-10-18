import SwiftUI

/// Settings › Keep Awake, in the reference app's row style, opening with what it's doing right now.
struct KeepAwakeSettingsPage: View {
    static let modeRow = SettingsRowID("keepAwake.mode")
    static let timerRow = SettingsRowID("keepAwake.timer")
    static let displayRow = SettingsRowID("keepAwake.display")
    static let batteryRow = SettingsRowID("keepAwake.battery")

    /// Wide enough for "While Agents Work".
    static let selectWidth: CGFloat = 170

    let controller: KeepAwakeController

    var body: some View {
        @Bindable var controller = controller
        SettingsPage {
            SettingsHeader("Keep Awake", description: Text("Stop your Mac from sleeping so long agent runs finish."))
            SettingsRowGroup {
                SettingsRow(
                    id: Self.modeRow,
                    "Keep Mac awake",
                    description: Text("Prevents idle sleep. Closing the lid still puts your Mac to sleep."),
                    detail: Text(controller.status.description(keepsDisplayOn: controller.keepsDisplayOn))
                ) {
                    SettingsSelect(
                        label: "Keep Mac awake",
                        selection: $controller.mode,
                        options: KeepAwakeMode.allCases.map { .init(value: $0, title: $0.title) },
                        width: Self.selectWidth
                    )
                }
                SettingsRow(
                    id: Self.timerRow,
                    "Stay awake for a while",
                    description: Text("Keeps your Mac awake for a set time whatever the mode, then goes back to it."),
                    detail: controller.awakeUntil.map { Text("Awake until \(DSFormat.timeAndCountdown($0, now: .now)).") }
                ) {
                    timerControl
                }
                SettingsRow(
                    id: Self.displayRow,
                    "Keep display on",
                    description: Text("Also stop the display from dimming and sleeping while your Mac is kept awake.")
                ) {
                    SettingsSwitch("Keep display on", isOn: $controller.keepsDisplayOn)
                }
                SettingsRow(
                    id: Self.batteryRow,
                    "On battery",
                    description: Text("What to do when your Mac isn't plugged in.")
                ) {
                    SettingsSelect(
                        label: "On battery",
                        selection: $controller.battery,
                        options: KeepAwakeBatteryRule.allCases.map { .init(value: $0, title: $0.title) },
                        width: Self.selectWidth
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var timerControl: some View {
        if controller.awakeUntil != nil {
            Button("Cancel Timer") {
                controller.cancelTimer()
            }
        } else {
            Menu("Start Timer") {
                ForEach(KeepAwakeController.timerDurations, id: \.self) { duration in
                    Button(duration.keepAwakeTitle) {
                        controller.stayAwake(for: duration)
                    }
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
        }
    }
}
