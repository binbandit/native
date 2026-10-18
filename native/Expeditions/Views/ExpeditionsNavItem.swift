import NativeCommands
import SwiftUI

/// "Expeditions" in the sidebar's top half. It counts the expeditions waiting on the user.
struct ExpeditionsNavItem: View {
    let isSelected: Bool
    let action: () -> Void

    @Environment(ExpeditionCenter.self) private var center

    var body: some View {
        let waiting = center.waitingCount
        SidebarNavItem(
            "Expeditions", systemImage: ExpeditionsMetrics.symbol, isSelected: isSelected, shortcut: CommandRegistry.shared.shortcut(for: .goExpeditions)?.displayString,
            action: action
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

enum ExpeditionsMetrics {
    /// A route from one point to another: the feature's glyph wherever it appears.
    static let symbol = "point.topleft.down.to.point.bottomright.curvepath"
    static let inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (340, 440, 640)
    /// The crew and logbook column beside the route on wide windows.
    static let sideColumn: CGFloat = 280
}
