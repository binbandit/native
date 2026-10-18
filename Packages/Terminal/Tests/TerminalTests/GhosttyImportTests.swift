import Foundation
import Testing

@testable import Terminal

struct GhosttyImportTests {
    private let home = URL(filePath: "/Users/someone")

    private var locations: GhosttyConfigLocations {
        GhosttyConfigLocations(
            environment: [:], home: home, bundledThemes: URL(filePath: "/Applications/Ghostty.app/themes"))
    }

    private func file(_ text: String, at path: String = "/Users/someone/.config/ghostty/config") -> GhosttyConfigFile {
        GhosttyConfigFile(url: URL(filePath: path), text: text)
    }

    @Test func findsTheDefaultFilesWhereGhosttyLooks() {
        let xdg = GhosttyConfigLocations(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: home, bundledThemes: nil)
        #expect(
            xdg.defaultFiles.map(\.path) == [
                "/tmp/xdg/ghostty/config", "/tmp/xdg/ghostty/config.ghostty",
                "/Users/someone/Library/Application Support/com.mitchellh.ghostty/config",
                "/Users/someone/Library/Application Support/com.mitchellh.ghostty/config.ghostty",
            ])
        #expect(
            locations.themeFiles(named: "Dracula").map(\.path) == [
                "/Users/someone/.config/ghostty/themes/Dracula", "/Applications/Ghostty.app/themes/Dracula",
            ])
        #expect(locations.themeFiles(named: "/tmp/mine").map(\.path) == ["/tmp/mine"])
    }

    @Test func readsEntriesIncludesAndQuotes() {
        let config = file(
            """
            # comment
            font-family = "JetBrains Mono"
            config-file = ?local.conf
            config-file = ~/shared/ghostty
            not a setting
            """)
        #expect(config.entries.map(\.key) == ["font-family", "config-file", "config-file"])
        #expect(config.entries[0].value == "JetBrains Mono")
        #expect(config.entries[0].line == 2)
        #expect(
            config.includes(home: home).map(\.path) == [
                "/Users/someone/.config/ghostty/local.conf", "/Users/someone/shared/ghostty",
            ])
    }

    @Test func namesTheLineADiagnosticIsAbout() {
        let config = file("theme = Nope\nwindow-padding-x = banana\n")
        #expect(
            GhosttyConfigFile.locate("window-padding-x: invalid value \"banana\"", in: [config])
                == "/Users/someone/.config/ghostty/config:2: window-padding-x: invalid value \"banana\"")
        #expect(
            GhosttyConfigFile.locate("theme \"Nope\" not found, tried path \"x\"", in: [config])
                .hasPrefix("/Users/someone/.config/ghostty/config:1: "))
        #expect(GhosttyConfigFile.locate("something else", in: [config]) == "something else")
    }

    @Test func quotesTheShellAndResolvesTheLoginShell() {
        #expect(TerminalShell.command(for: "/opt/homebrew/bin/fish") == "/opt/homebrew/bin/fish")
        #expect(TerminalShell.command(for: "/a b/it's") == "'/a b/it'\\''s'")
        #expect(TerminalShell.login.path(loginShell: "/bin/zsh") == "/bin/zsh")
        #expect(TerminalShell.path("/bin/bash").path(loginShell: "/bin/zsh") == "/bin/bash")
    }

    @Test func reduceTransparencyMakesTheTerminalOpaque() {
        #expect(TerminalTransparency(backgroundOpacity: 0.8, forcesOpaque: true).backgroundOpacity == 1)
        let forced = GhosttyConfiguration.userConfigOverrides(TerminalTransparency(forcesOpaque: true))
        #expect(forced.contains("background-opacity = 1"))
        #expect(!GhosttyConfiguration.userConfigOverrides(.opaque).contains("background-opacity"))
    }

    @Test func loadsIncludesAfterTheFilesThatNameThem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ghostty-import-\(UUID())")
        let config = directory.appending(path: "ghostty")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "config-file = extra\nfont-size = 13\n".write(
            to: config.appending(path: "config"), atomically: true, encoding: .utf8)
        try "font-size = 15\n".write(to: config.appending(path: "extra"), atomically: true, encoding: .utf8)
        let locations = GhosttyConfigLocations(
            environment: ["XDG_CONFIG_HOME": directory.path], home: home, bundledThemes: nil)
        let files = GhosttyConfigFile.load(locations, home: home)
        #expect(files.map(\.url.lastPathComponent) == ["config", "extra"])
        #expect(GhosttyImporter.read(files, locations: locations, theme: { _ in nil }).fontSize == 15)
    }

    @Test func importsFontCursorAndScrollback() {
        let result = GhosttyImporter.read(
            [
                file(
                    """
                    font-family = Menlo
                    font-family =
                    font-family = Berkeley Mono
                    font-family = Symbols Nerd Font
                    font-size = 14
                    cursor-style = bar
                    cursor-style-blink = false
                    scrollback-limit-lines = 25000
                    """)
            ], locations: locations, theme: { _ in nil })
        #expect(result.fontFamily == "Berkeley Mono")
        #expect(result.fontSize == 14)
        #expect(result.cursor == TerminalCursor(style: .bar, blinks: false))
        #expect(result.scrollback == .lines(25000))
        #expect(result.colors == nil)
    }

    @Test func importsAThemeAndLetsTheConfigsOwnColorsWin() {
        let dracula =
            "palette = 1=#ff5555\nbackground = #282a36\nforeground = #f8f8f2\nselection-background = #44475a\n"
        var asked: [String] = []
        let result = GhosttyImporter.read(
            [file("theme = light:GitHub Light,dark:Dracula\nbackground = #101010\n")], locations: locations,
            theme: { urls in
                asked.append(urls[0].lastPathComponent)
                return urls[0].lastPathComponent == "Dracula" ? dracula : nil
            })
        let colors = result.colors
        #expect(colors?.themeName == "light:GitHub Light,dark:Dracula")
        #expect(colors?.themeTitle == "GitHub Light (light), Dracula (dark)")
        #expect(colors?.dark.palette[1] == TerminalRGB(0xFF5555))
        #expect(colors?.dark.chrome.background == TerminalRGB(0x101010))
        #expect(colors?.dark.chrome.selectionBackground == TerminalRGB(0x44475A))
        // A theme that can't be found leaves Ghostty's defaults under the config's own colors.
        #expect(colors?.light.palette[1] == TerminalRGB(0xCC6666))
        #expect(asked.sorted() == ["Dracula", "GitHub Light"])
    }

    @Test func importsNothingFromAnEmptyConfigAndAppliesOnlyWhatItFound() {
        let empty = GhosttyImporter.read([file("# nothing\n")], locations: locations, theme: { _ in nil })
        #expect(empty.isEmpty)
        let sizeOnly = TerminalImport(fontSize: 16)
        let before = TerminalSettings(fontFamily: "Menlo", fontSize: 12)
        let after = sizeOnly.applied(to: before)
        #expect(after.fontFamily == "Menlo")
        #expect(after.fontSize == 16)
    }
}
