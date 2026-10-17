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

    @Environment(\.openSettings) private var openSettings

    private var description: String {
        controller.status.description(keepsDisplayOn: controller.keepsDisplayOn)
    }

    var body: some View {
        Menu {
            KeepAwakeMenuItems(controller: controller)
            Divider()
            Button("Keep-Awake Settings…") {
                openSettings()
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
        .help("Keep Mac awake: \(description)")
        .accessibilityLabel("Keep Mac awake")
        .accessibilityValue("\(controller.mode.title). \(description)")
    }

    /// The mode, or while a timer runs, the time left on it ("1h 24m"), updated each minute.
    @ViewBuilder
    private var label: some View {
        if let until = controller.awakeUntil {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(Duration.seconds(max(until.timeIntervalSince(context.date), 0)).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
            }
        } else {
            Text(controller.mode.shortTitle)
        }
    }
}
