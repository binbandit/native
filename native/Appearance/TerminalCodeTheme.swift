import CodeThemes
import SwiftUI
import Terminal

extension View {
    /// Gives the terminal the user's code themes as its app theme (`TerminalStore.appTheme`), the one
    /// input the terminal takes from them; the terminal decides precedence (the user's Ghostty
    /// settings, or colors imported from Ghostty, win). With "Use the same font in the terminal" on,
    /// it also keeps the terminal's font family and size on the code font.
    func terminalCodeTheme(_ terminals: TerminalStore) -> some View {
        modifier(TerminalCodeThemeModifier(terminals: terminals))
    }
}

private struct TerminalCodeThemeModifier: ViewModifier {
    let terminals: TerminalStore

    @Environment(\.dsCodeThemes) private var codeThemes
    @Environment(\.dsCodeFont) private var codeFont
    @AppStorage(AppearancePreferences.terminalUsesCodeFontKey) private var terminalUsesCodeFont = false

    func body(content: Content) -> some View {
        content
            .onChange(of: codeThemes, initial: true) { _, themes in
                terminals.appTheme = TerminalTheme(themes)
            }
            .onChange(of: TerminalFontSync(font: codeFont, isOn: terminalUsesCodeFont), initial: true) { _, sync in
                guard sync.isOn else { return }
                var settings = terminals.preferences.settings
                // The terminal's nil family is the app's code font, Geist Mono.
                settings.fontFamily = sync.font.family.isEmpty ? nil : sync.font.family
                settings.fontSize = sync.font.size
                if settings != terminals.preferences.settings {
                    terminals.preferences.settings = settings
                }
            }
    }
}

private struct TerminalFontSync: Equatable {
    let font: DSCodeFont
    let isOn: Bool
}

extension TerminalTheme {
    /// The terminal's colors for the chosen code themes: Native's own terminal theme where the code
    /// theme is Native, and otherwise the theme's background and text with ANSI colors from its roles.
    init(_ themes: DSCodeThemes) {
        func variant(_ theme: CodeTheme, _ appearance: CodeAppearance) -> Variant {
            guard theme.id != CodeTheme.native.id, let palette = theme.palette(for: appearance) else {
                return appearance == .dark ? TerminalTheme.native.dark : TerminalTheme.native.light
            }
            func rgb(_ color: CodeColor) -> TerminalRGB {
                TerminalRGB(red: color.red, green: color.green, blue: color.blue)
            }
            var variant = Variant(palette: palette.ansiColors(for: appearance).map(\.rgb))
            variant.chrome = TerminalChrome(
                background: rgb(palette.background), foreground: rgb(palette.foreground),
                cursor: rgb(palette.foreground),
                cursorText: rgb(palette.background),
                selectionBackground: rgb(palette.selection.composited(over: palette.background)))
            return variant
        }
        self.init(
            id: "code:\(themes.light.id.rawValue)|\(themes.dark.id.rawValue)",
            name: themes.light.id == themes.dark.id ? themes.light.name : "\(themes.light.name) / \(themes.dark.name)",
            light: variant(themes.light, .light), dark: variant(themes.dark, .dark))
    }
}

extension CodeColor {
    fileprivate var rgb: UInt32 { UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue) }
}
