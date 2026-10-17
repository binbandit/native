import SwiftUI

/// A 1pt rule in the separator color, between regions and list sections.
public struct SeparatorLine: View {
    let axis: Axis

    public init(axis: Axis = .horizontal) {
        self.axis = axis
    }

    public var body: some View {
        Rectangle()
            .fill(.dsSeparator)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
            .accessibilityHidden(true)
    }
}

#Preview("Separator") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            Text("Above").font(.dsBody).foregroundStyle(.dsTextSecondary)
            SeparatorLine()
            Text("Below").font(.dsBody).foregroundStyle(.dsTextSecondary)
        }
        .frame(width: 200)
    }
}
