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

extension View {
    /// Sets the view off as the trailing segment of a header or capsule, after a hairline of
    /// `height`: the well's progress or Review, Peek's Open Task.
    public func dsTrailingSegment(inset: CGFloat, dividerHeight: CGFloat) -> some View {
        padding(.leading, inset)
            .overlay(alignment: .leading) {
                SeparatorLine(axis: .vertical).frame(height: dividerHeight)
            }
    }
}

#Preview("Separator") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            Text("Above").font(.dsBody).foregroundStyle(.dsTextSecondary)
            SeparatorLine()
            Text("Below").font(.dsBody).foregroundStyle(.dsTextSecondary)
            HStack {
                Text("Leading").font(.dsBody).foregroundStyle(.dsTextSecondary)
                Text("Segment").font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .dsTrailingSegment(inset: DS.Space.md, dividerHeight: DS.Space.lg)
            }
        }
        .frame(width: 200)
    }
}
