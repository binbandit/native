import SwiftUI

/// The Beta edition of Native's emblem, from `design/app-icon/Beta.icon`: the left link amber and
/// the right one cream, or dark brown on a light page, in the icon's own colors. Lays out exactly
/// like `NativeMark`.
public struct NativeBetaMark: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            NativeMark(link: .left)
                .fill(isDark ? Self.rgb(1, 0.73725, 0.30980) : Self.rgb(0.6, 0.35686, 0.05098))
            NativeMark(link: .right)
                .fill(isDark ? Self.rgb(1, 0.94118, 0.80784) : Self.rgb(0.18824, 0.16078, 0.12157))
        }
        .aspectRatio(NativeMark.aspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Native Beta")
        .accessibilityAddTraits(.isImage)
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

#Preview("Beta mark") {
    DSPreviewPair {
        NativeBetaMark()
            .frame(width: 96, height: 62)
            .padding(DS.Space.xxl)
    }
}
