import Modes
import NativeCommands
import SwiftUI

/// The task's mode in the composer: its symbol and name (just the symbol when the composer is short
/// of room), filled while it's anything but Build. A click opens `ModePicker`; ⌃⇧M steps to the
/// next mode.
struct ModePill: View {
    let control: TaskModeControl
    var showsIcon = false

    @State private var isPickerOpen = false

    var body: some View {
        let mode = control.current
        Button {
            isPickerOpen.toggle()
        } label: {
            Label(mode.name, systemImage: mode.symbol)
        }
        .buttonStyle(.pill(isOn: mode.id != .build, isSquare: showsIcon, isOpen: isPickerOpen))
        .help(help(for: mode))
        .accessibilityLabel("Mode: \(mode.name)")
        .accessibilityHint("Shows the modes")
        .popover(isPresented: $isPickerOpen, arrowEdge: .top) {
            ModePicker(control: control) {
                isPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }

    private func help(for mode: Mode) -> String {
        let next = CommandRegistry.shared.shortcut(for: .sessionNextMode).map {
            " Press \($0.displayString) for the next mode."
        }
        return "\(mode.label): \(mode.summary).\(next ?? "")"
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Mode pill") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            if let build = ModesPreviewFixtures.control(), let plan = ModesPreviewFixtures.control(planning: true) {
                ModePill(control: build)
                ModePill(control: plan)
                ModePill(control: plan, showsIcon: true)
            }
        }
    }
    .environment(SettingsPresentation())
}
#endif
