import NativeAutomation
import SwiftUI

/// "Automations" in the sidebar's top half: the one place every automation can be seen and stopped.
/// It counts the runs waiting on the user.
struct AutomationsNavItem: View {
    let isSelected: Bool
    let action: () -> Void

    @Environment(AutomationCenter.self) private var center

    var body: some View {
        let waiting = center.automations.book.runs.count { $0.status == .needsYou }
        SidebarNavItem("Automations", systemImage: "clock.arrow.circlepath", isSelected: isSelected, action: action) {
            if waiting > 0 {
                Text("\(waiting)")
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsAttention)
                    .padding(.horizontal, DS.Space.xs)
                    .frame(minWidth: DS.Size.rowLeading, minHeight: DS.Size.statusGlyph)
                    .background(.dsSelected, in: .capsule)
                    .padding(.trailing, DS.Space.sm)
                    .help("\(waiting) waiting on you")
                    .accessibilityLabel("\(waiting) waiting on you")
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Automations nav item") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            AutomationsNavItem(isSelected: false) {}
            AutomationsNavItem(isSelected: true) {}
        }
        .frame(width: DS.Size.sidebarWidth)
    }
    .environment(AutomationCenter.preview())
}
#endif
