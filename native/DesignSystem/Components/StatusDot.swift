import SwiftUI

/// A 6pt dot: the reference app's unread mark in the sidebar and the connectors' health in the composer.
public struct StatusDot: View {
    let color: Color

    public init(color: Color = .dsAccent) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

#Preview("Status dots") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            StatusDot()
            StatusDot(color: .dsSuccess)
            StatusDot(color: .dsTextTertiary)
        }
    }
}
