import SwiftUI

/// Which Día de Muertos Home mark to draw: one per release channel, like the Halloween editions. The
/// links take cempasúchil orange and a channel color; the paper flags, marigolds and candlelight
/// stay the same, so every channel reads as one family.
public enum NativeMuertosEdition: CaseIterable, Sendable {
    /// Marigold and rosa mexicano.
    case regular
    /// Marigold and the Beta icon's cream.
    case beta
    /// Marigold and Nightly lavender, under the night sky.
    case nightly

    /// The colors of one edition in one appearance. Petals and flags are shared across editions.
    struct Palette {
        /// The left link, top to bottom of its gradient.
        let marigoldLink: (top: Color, bottom: Color)
        /// The right link.
        let channelLink: (top: Color, bottom: Color)
        /// Papel picado, left to right.
        let flags: [Color]
        let string: Color
        /// Outer petals, inner petals and the blossom's heart.
        let petals: (outer: Color, inner: Color, heart: Color)
        let flame: (outer: Color, core: Color)
        let wax: Color
        let glow: Color
        let glowOpacity: Double
    }

    func palette(isDark: Bool) -> Palette {
        let violet = isDark ? Self.rgb(0.68, 0.53, 0.92) : Self.rgb(0.42, 0.25, 0.65)
        let rosa = isDark ? Self.rgb(0.95, 0.42, 0.64) : Self.rgb(0.80, 0.19, 0.45)
        let marigold = isDark ? Self.rgb(1, 0.70, 0.25) : Self.rgb(0.91, 0.50, 0.08)
        return Palette(
            marigoldLink: isDark
                ? (Self.rgb(1, 0.76, 0.30), Self.rgb(1, 0.54, 0.12))
                : (Self.rgb(0.95, 0.58, 0.13), Self.rgb(0.82, 0.38, 0.04)),
            channelLink: channelLink(isDark: isDark),
            flags: [violet, rosa, marigold, rosa, violet],
            string: isDark ? Self.rgb(0.95, 0.88, 0.74, 0.55) : Self.rgb(0.35, 0.25, 0.18, 0.45),
            petals: isDark
                ? (Self.rgb(1, 0.56, 0.10), Self.rgb(1, 0.79, 0.29), Self.rgb(0.71, 0.32, 0.10))
                : (Self.rgb(0.90, 0.45, 0.05), Self.rgb(0.98, 0.67, 0.14), Self.rgb(0.55, 0.23, 0.04)),
            flame: (Self.rgb(1, 0.66, 0.20), Self.rgb(1, 0.93, 0.66)),
            wax: isDark ? Self.rgb(1, 0.95, 0.83) : Self.rgb(0.93, 0.80, 0.58),
            glow: Self.rgb(1, 0.66, 0.22),
            glowOpacity: isDark ? 0.26 : 0.16
        )
    }

    private func channelLink(isDark: Bool) -> (top: Color, bottom: Color) {
        switch (self, isDark) {
        case (.regular, false): (Self.rgb(0.82, 0.22, 0.48), Self.rgb(0.62, 0.11, 0.35))
        case (.regular, true): (Self.rgb(0.97, 0.47, 0.68), Self.rgb(0.88, 0.25, 0.52))
        // The Beta icon's cream, or its dark brown on a light page.
        case (.beta, false): (Self.rgb(0.25, 0.21, 0.16), Self.rgb(0.19, 0.16, 0.12))
        case (.beta, true): (Self.rgb(1, 0.96, 0.86), Self.rgb(1, 0.91, 0.76))
        case (.nightly, false): (Self.rgb(0.47, 0.35, 0.62), Self.rgb(0.33, 0.23, 0.45))
        case (.nightly, true): (Self.rgb(0.80, 0.72, 0.96), Self.rgb(0.66, 0.56, 0.90))
        }
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
