import NativeHostProtocol
import SwiftUI

/// The keep-awake choices as menu items, shared by the status bar's menu and View ▸ Keep Mac Awake:
/// what it's doing now, the three modes with their descriptions, a timer, and the display.
struct KeepAwakeMenuItems: View {
    let controller: KeepAwakeController

    var body: some View {
        @Bindable var controller = controller
        Section(controller.status.description(keepsDisplayOn: controller.keepsDisplayOn)) {
            // Toggles rather than a picker: their two-text labels become a title and the
            // description as a subtitle, which a picker's options drop.
            ForEach(KeepAwakeMode.choices.reversed()) { mode in
                Toggle(
                    isOn: Binding {
                        controller.mode == mode
                    } set: {
                        if $0 { controller.setMode(mode) }
                    }
                ) {
                    Text(mode.title)
                    Text(mode.explanation)
                }
            }
        }
        Section {
            Menu("Stay Awake For") {
                ForEach(KeepAwakeController.timerDurations, id: \.self) { duration in
                    Button(duration.keepAwakeTitle) {
                        controller.stayAwake(for: duration)
                    }
                }
            }
            if controller.awakeUntil != nil {
                Button("Cancel Timer") {
                    controller.cancelTimer()
                }
            }
            Toggle("Keep Display On", isOn: $controller.keepsDisplayOn)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Keep awake menu") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            Menu("While agents work") {
                KeepAwakeMenuItems(controller: KeepAwakePreviewFixtures.working())
            }
            // With a timer running, Cancel Timer joins the menu.
            Menu("Timer") {
                KeepAwakeMenuItems(controller: KeepAwakePreviewFixtures.timer())
            }
        }
        .fixedSize()
    }
}
#endif
