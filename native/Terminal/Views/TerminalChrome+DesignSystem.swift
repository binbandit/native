import SwiftUI
import Terminal

extension TerminalChrome {
    /// The terminal's background, text, cursor and selection from the design system, so it sits
    /// in the window like the rest of the content: the sunken surface code blocks use, primary
    /// text, an accent cursor, and an accent-tinted selection.
    static func designSystem(appearance: TerminalAppearance, palette: DSAccentPalette) -> TerminalChrome {
        var environment = EnvironmentValues()
        environment.colorScheme = appearance == .dark ? .dark : .light
        environment.dsAccentPalette = palette
        let background = TerminalRGB(Color.dsSurfaceSunken, in: environment)
        let accent = TerminalRGB(Color.dsAccent, in: environment)
        return TerminalChrome(
            background: background,
            foreground: TerminalRGB(Color.dsTextPrimary, in: environment),
            cursor: accent,
            cursorText: TerminalRGB(Color.dsTextOnAccent, in: environment),
            selectionBackground: accent.over(background, opacity: selectionOpacity)
        )
    }

    /// Strong enough to read as a selection on either appearance, light enough to keep text legible.
    private static let selectionOpacity = 0.28
}

extension TerminalAppearance {
    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }
}

extension TerminalRGB {
    /// A design-system color as it resolves in `environment`, in sRGB.
    init(_ color: Color, in environment: EnvironmentValues) {
        let resolved = color.resolve(in: environment)
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = resolved.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
            let components = converted.components, components.count >= 3
        else {
            self.init(0x000000)
            return
        }
        self.init(fractionalRed: components[0], green: components[1], blue: components[2])
    }
}
