import Testing

@testable import Terminal

struct TerminalThemeTests {
    private let appChrome = TerminalChrome(
        background: TerminalRGB(0xF6F6F6), foreground: TerminalRGB(0x181818), cursor: TerminalRGB(0x202226),
        cursorText: TerminalRGB(0xFFFFFF), selectionBackground: TerminalRGB(0xCACBCC)
    )

    @Test func nativeTakesItsChromeFromTheApp() {
        let light = TerminalTheme.native.colors(for: .light, appChrome: appChrome)
        #expect(light.chrome == appChrome)
        #expect(light.palette.count == 16)
        #expect(light.palette[1] == TerminalRGB(0xCF222E))
        #expect(TerminalTheme.native.colors(for: .dark, appChrome: appChrome).palette[1] == TerminalRGB(0xF87272))
    }

    @Test func aThemeWithItsOwnChromeKeepsIt() {
        let own = TerminalChrome(
            background: TerminalRGB(0x282A36), foreground: TerminalRGB(0xF8F8F2), cursor: TerminalRGB(0xF8F8F2),
            cursorText: TerminalRGB(0x282A36), selectionBackground: TerminalRGB(0x44475A)
        )
        let palette: [UInt32] = Array(repeating: 0x000000, count: 16)
        let theme = TerminalTheme(
            id: "test", name: "Test", light: .init(palette: palette), dark: .init(palette: palette, chrome: own))
        #expect(theme.colors(for: .dark, appChrome: appChrome).chrome == own)
        #expect(theme.colors(for: .light, appChrome: appChrome).chrome == appChrome)
    }

    @Test func importedColorsReplaceTheAppTheme() {
        let dracula = TerminalColors(
            chrome: TerminalChrome(
                background: TerminalRGB(0x282A36), foreground: TerminalRGB(0xF8F8F2), cursor: TerminalRGB(0xF8F8F2),
                cursorText: TerminalRGB(0x282A36), selectionBackground: TerminalRGB(0x44475A)),
            palette: Array(repeating: TerminalRGB(0x000000), count: 16))
        let imported = TerminalSettings(
            colors: .imported(TerminalImportedColors(themeName: "Dracula", light: dracula, dark: dracula)))
        let style = TerminalStyle(settings: imported, appearance: .light, appTheme: .native, appChrome: appChrome)
        #expect(style.colors == dracula)
        let app = TerminalStyle(settings: TerminalSettings(), appearance: .light, appTheme: .native, appChrome: appChrome)
        #expect(app.colors.chrome == appChrome)
    }

    @Test func formatsAndBlendsColors() {
        #expect(TerminalRGB(0x0A0B0C).description == "#0a0b0c")
        #expect(TerminalRGB(fractionalRed: 1.2, green: 0.5, blue: -0.1) == TerminalRGB(red: 255, green: 128, blue: 0))
        #expect(TerminalRGB(0xFFFFFF).over(TerminalRGB(0x000000), opacity: 0.5) == TerminalRGB(0x808080))
    }

    @Test func settingsKeepFontSizesInRangeAndEmptyFamiliesUnset() {
        #expect(TerminalSettings(fontSize: 100).fontSize == TerminalSettings.fontSizes.upperBound)
        #expect(TerminalSettings(fontFamily: "").fontFamily == nil)
        #expect(TerminalScrollback(storedValue: 0) == .unlimited)
        #expect(TerminalScrollback(storedValue: TerminalScrollback.lines(1000).storedValue) == .lines(1000))
    }
}
