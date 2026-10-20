import NativeAutomation
import SwiftUI

/// "Workflows" in the sidebar's top half, opening the runs and the library. It counts the runs that
/// are waiting on the user.
struct WorkflowsNavItem: View {
    let isSelected: Bool
    let action: () -> Void

    @Environment(AutomationCenter.self) private var center

    var body: some View {
        let waiting = center.workflows.runs.count { $0.phase.needsUser }
        SidebarNavItem(
            "Workflows", systemImage: "point.3.connected.trianglepath.dotted", isSelected: isSelected, action: action
        ) {
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
#Preview("Workflows nav item") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            WorkflowsNavItem(isSelected: false) {}
            WorkflowsNavItem(isSelected: true) {}
        }
        .frame(width: DS.Size.sidebarWidth)
    }
    .environment(AutomationCenter.preview())
}
#endif
