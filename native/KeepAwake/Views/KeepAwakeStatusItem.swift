import SwiftUI

/// Orca's caffeinate segment: a cup, the mode (or the time left on a timer) and a dot that's lit
/// while the Mac is being kept awake. Click for the choices.
struct KeepAwakeStatusItem: StatusBarItem {
    let controller: KeepAwakeController

    let id = "keepAwake"
    let title = "Keep Mac Awake"
    let placement = StatusBarPlacement.trailing
    let order = 10

    var content: some View {
        KeepAwakeSegment(controller: controller)
    }
}

private struct KeepAwakeSegment: View {
    let controller: KeepAwakeController

    @Environment(SettingsPresentation.self) private var settings

    private var description: String {
        controller.status.description(keepsDisplayOn: controller.keepsDisplayOn)
    }

    var body: some View {
        Menu {
            KeepAwakeMenuItems(controller: controller)
            Divider()
            Button("Keep-Awake Settings…") {
                settings.open(.keepAwake)
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                StatusBarGlyph(controller.status.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(controller.status.isActive ? .dsTextPrimary : .dsTextSecondary)
                label
                StatusDot(color: controller.status.isActive ? .dsTextPrimary : .dsTextQuaternary)
            }
            .statusBarSegmentChrome()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(description)
        .accessibilityLabel("Keep Mac awake")
        .accessibilityValue("\(controller.mode.title). \(description)")
    }

    /// The mode, or while a timer runs, when it ends ("Until 5:40 PM").
    private var label: Text {
        if let until = controller.awakeUntil {
            Text("Until \(DSFormat.time(until, now: .now))")
        } else {
            Text(controller.mode.shortTitle)
        }
    }
}
