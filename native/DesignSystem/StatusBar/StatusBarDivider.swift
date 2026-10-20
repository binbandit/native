import SwiftUI

/// The faint dot between two figures in one status-bar item ("745.7 MB · 2%").
public struct StatusBarDivider: View {
    public init() {}

    public var body: some View {
        Text("·")
            .foregroundStyle(.dsTextQuaternary)
            .accessibilityHidden(true)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Status bar divider") {
    DSPreviewPair {
        VStack(spacing: 0) {
            Color.dsBackground.frame(width: 320, height: 40)
            StatusBarDivider()
                .frame(width: 320)
        }
    }
}
#endif
