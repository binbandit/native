import SwiftUI

/// Which Halloween app icon to match: one per release channel, each with its own colors.
public enum NativeHalloweenEdition: CaseIterable, Sendable {
    /// Orange and cream ghosts.
    case regular
    /// Lime and cream ghosts.
    case beta
    /// Lavender and cream ghosts under an orange moon.
    case nightly

    /// The colors of one edition in one appearance.
    struct Palette {
        let upperFold: Color
        let lowerFold: Color
    }

    /// The icons' fold colors (`icon.json`). On a light page the Regular icon's cream ghost would
    /// vanish, so it takes the icon's orange tile color instead; every other color is the icon's own.
    func palette(isDark: Bool) -> Palette {
        switch (self, isDark) {
        case (.regular, false):
            Palette(upperFold: Self.rgb(0.93725, 0.60392, 0.32549), lowerFold: Self.rgb(0.26667, 0.16471, 0.14118))
        case (.regular, true):
            Palette(upperFold: Self.rgb(1, 0.94118, 0.84706), lowerFold: Self.rgb(1, 0.62745, 0.32157))
        case (.beta, false):
            Palette(upperFold: Self.rgb(0.20392, 0.29804, 0.22745), lowerFold: Self.rgb(0.45098, 0.51373, 0.18431))
        case (.beta, true):
            Palette(upperFold: Self.rgb(0.95294, 0.96078, 0.83137), lowerFold: Self.rgb(0.76471, 0.92941, 0.45490))
        case (.nightly, false):
            Palette(upperFold: Self.rgb(0.21569, 0.15686, 0.26275), lowerFold: Self.rgb(0.49412, 0.36078, 0.61176))
        case (.nightly, true):
            Palette(upperFold: Self.rgb(0.98431, 0.92941, 0.84706), lowerFold: Self.rgb(0.74118, 0.65490, 0.93725))
        }
    }

    /// The Nightly icon's moon, its craters (`moon-detail.svg`, 27%) and the bat across it.
    static func moonColors(isDark: Bool) -> (moon: Color, craters: Color, bat: Color) {
        isDark
            ? (rgb(0.90588, 0.60392, 0.40000), rgb(0.63137, 0.36471, 0.28627, 0.27), rgb(0.18824, 0.14118, 0.20784))
            : (rgb(0.86667, 0.63922, 0.42353), rgb(0.61176, 0.38039, 0.23922, 0.27), rgb(0.46667, 0.32549, 0.40392))
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
