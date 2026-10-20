import SwiftUI

/// Colors for the two links in each appearance, as a plugin icon set's palette gives them.
public struct NativeTwoTonePalette: Equatable, Sendable {
    public let light: (left: Color, right: Color)
    public let dark: (left: Color, right: Color)

    public init(light: (left: Color, right: Color), dark: (left: Color, right: Color)) {
        self.light = light
        self.dark = dark
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.light == rhs.light && lhs.dark == rhs.dark
    }
}

/// Native's emblem with each link in its own color, like `NativeBetaMark` but for any palette. Lays
/// out exactly like `NativeMark`.
public struct NativeTwoToneMark: View {
    let palette: NativeTwoTonePalette

    @Environment(\.colorScheme) private var colorScheme

    public init(palette: NativeTwoTonePalette) {
        self.palette = palette
    }

    public var body: some View {
        let colors = colorScheme == .dark ? palette.dark : palette.light
        ZStack {
            NativeMark(link: .left).fill(colors.left)
            NativeMark(link: .right).fill(colors.right)
        }
        .aspectRatio(NativeMark.aspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Native")
        .accessibilityAddTraits(.isImage)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Two-tone mark") {
    DSPreviewPair {
        NativeTwoToneMark(palette: NativeTwoTonePalette(light: (.dsAccent, .dsWarning), dark: (.dsAccent, .dsWarning)))
            .frame(width: 96, height: 96)
    }
}
#endif
