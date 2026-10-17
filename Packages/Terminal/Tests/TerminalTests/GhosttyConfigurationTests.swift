import Testing

@testable import Terminal

struct GhosttyConfigurationTests {
    private let chrome = TerminalChrome(
        background: TerminalRGB(0x1D1D1D), foreground: TerminalRGB(0xFFFFFF), cursor: TerminalRGB(0xECEDEF),
        cursorText: TerminalRGB(0x121316), selectionBackground: TerminalRGB(0x4E4F51)
    )

    private func configuration(_ settings: TerminalSettings = TerminalSettings()) -> GhosttyConfiguration {
        GhosttyConfiguration(
            settings: settings,
            colors: TerminalTheme.native.colors(for: .dark, appChrome: chrome),
            defaultFont: .init(family: "Geist Mono", isVariable: true),
            padding: .init(horizontal: 8, vertical: 6)
        )
    }

    private func values(of key: String, in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && parts[0] == key ? parts[1] : nil
        }
    }

    @Test func usesTheAppsCodeFontUnlessTheUserPickedOne() {
        let standard = configuration().text
        #expect(values(of: "font-family", in: standard) == ["\"Geist Mono\""])
        #expect(values(of: "font-variation", in: standard) == ["wght=400"])
        let custom = configuration(TerminalSettings(fontFamily: "JetBrains Mono", fontSize: 14)).text
        #expect(values(of: "font-family", in: custom) == ["\"JetBrains Mono\""])
        #expect(values(of: "font-variation", in: custom).isEmpty)
        #expect(values(of: "font-size", in: custom) == ["14"])
    }

    @Test func writesTheChromeAndAllSixteenPaletteColors() {
        let text = configuration().text
        #expect(values(of: "background", in: text) == ["#1d1d1d"])
        #expect(values(of: "foreground", in: text) == ["#ffffff"])
        #expect(values(of: "cursor-color", in: text) == ["#ecedef"])
        let palette = values(of: "palette", in: text)
        #expect(palette.count == 16)
        #expect(palette.first == "0=#484f58")
        #expect(palette.last == "15=#ffffff")
    }

    @Test func limitsScrollbackByLinesOnly() {
        let limited = configuration(TerminalSettings(scrollback: .lines(50000))).text
        #expect(values(of: "scrollback-limit-lines", in: limited) == ["50000"])
        #expect(values(of: "scrollback-limit-bytes", in: limited) == ["unlimited"])
        let unlimited = configuration(TerminalSettings(scrollback: .unlimited)).text
        #expect(values(of: "scrollback-limit-lines", in: unlimited) == ["unlimited"])
    }

    @Test func clearsGhosttysBindingsBeforeAddingTerminalOnes() {
        let bindings = values(of: "keybind", in: configuration().text)
        #expect(bindings.first == "clear")
        #expect(bindings.contains("performable:super+k=clear_screen"))
        // Keys the app owns never come back.
        #expect(!bindings.contains { $0.hasPrefix("super+w") || $0.hasPrefix("super+n") || $0.hasPrefix("super+q") })
    }

    @Test func neverLetsAFontNameEndTheValueEarly() {
        #expect(GhosttyConfiguration.quoted("Bad\"Font\nName") == "\"BadFontName\"")
    }
}
