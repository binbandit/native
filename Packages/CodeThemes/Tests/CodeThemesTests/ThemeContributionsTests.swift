import Foundation
import Testing

@testable import CodeThemes

struct ThemeContributionsTests {
    private func object(_ palette: CodePalette) -> ThemeJSON {
        var members = Dictionary(
            uniqueKeysWithValues: CodeTokenRole.allCases.map {
                ($0.rawValue, ThemeJSON.string(palette[$0].description))
            })
        if !palette.strong.isEmpty {
            members["strong"] = .array(palette.strong.map { .string($0.rawValue) })
        }
        return .object(members)
    }

    private func codeEntry(_ theme: CodeTheme, id: String = "mine") -> ThemeJSON {
        var members: [String: ThemeJSON] = ["id": .string(id), "name": .string(theme.name)]
        members["light"] = theme.light.map(object)
        members["dark"] = theme.dark.map(object)
        return .object(members)
    }

    private let lightBackgrounds = [CodeColor(rgb: 0xFBFBFB), CodeColor(rgb: 0xF6F3EE)]
    private let darkBackgrounds = [CodeColor(rgb: 0x171717)]

    private func accentEntry(id: String = "sea", light: [String: String], dark: [String: String]) -> ThemeJSON {
        .object([
            "id": .string(id), "name": .string("Sea"),
            "light": .object(light.mapValues(ThemeJSON.string)), "dark": .object(dark.mapValues(ThemeJSON.string)),
        ])
    }

    private let lightSwatch = [
        "accent": "#2C5BA9", "hover": "#244B8C", "pressed": "#1B3A6E", "text": "#2C5BA9", "onAccent": "#FFFFFF",
        "subtle": "#ECF0F7",
    ]
    private let darkSwatch = [
        "accent": "#9DBCF0", "hover": "#AEC8F3", "pressed": "#7F9CCB", "text": "#9DBCF0", "onAccent": "#0D1A30",
        "subtle": "#222A38",
    ]

    @Test(arguments: CodeTheme.all)
    func everyBuiltInThemePassesThePluginChecks(_ theme: CodeTheme) throws {
        let result = try #require(ThemeContributions(code: [codeEntry(theme)]).codeThemes(namespace: "acme").first)
        let checked = try result.get()
        #expect(checked.id.rawValue == "acme/mine")
        #expect(checked.light == theme.light)
        #expect(checked.dark == theme.dark)
    }

    @Test func aBrokenThemeReportsItselfAndSparesTheOthers() throws {
        var missingRole = try #require(CodeTheme.dracula.dark.map(object))
        if case .object(var members) = missingRole {
            members["keyword"] = nil
            missingRole = .object(members)
        }
        let themes = ThemeContributions(code: [
            .object(["id": .string("broken"), "name": .string("Broken"), "dark": missingRole]),
            codeEntry(.nord, id: "fine"),
            .object(["id": .string("empty"), "name": .string("Empty")]),
            .string("not a theme"),
        ]).codeThemes(namespace: "acme")
        #expect(themes.count == 4)
        #expect(throws: ThemeProblemError.self) { try themes[0].get() }
        #expect("\(themes[0])".contains("no \"keyword\" color"))
        #expect(try themes[1].get().name == "Nord")
        #expect("\(themes[2])".contains("neither"))
        #expect("\(themes[3])".contains("isn't a JSON object"))
    }

    @Test func unreadableAndFaintColorsAreRejected() throws {
        let native = try #require(CodeTheme.native.light)
        func problem(_ role: CodeTokenRole, _ value: String) -> String {
            guard case .object(var members) = object(native) else { return "" }
            members[role.rawValue] = .string(value)
            let entry = ThemeJSON.object(["id": .string("x"), "name": .string("X"), "light": .object(members)])
            return "\(ThemeContributions(code: [entry]).codeThemes(namespace: "p")[0])"
        }
        #expect(problem(.keyword, "purple").contains("isn't a color"))
        guard case .object(var members) = object(native) else { return }
        members["strong"] = .array([.string("keyword"), .string("bold")])
        let strong = ThemeJSON.object(["id": .string("x"), "name": .string("X"), "light": .object(members)])
        #expect(
            "\(ThemeContributions(code: [strong]).codeThemes(namespace: "p")[0])".contains("\"bold\" that isn't a role")
        )
        #expect(problem(.foreground, "#F0F0F0").contains("text is too faint"))
        #expect(problem(.comment, "#F4F4F4").contains("\"comment\" color is too faint"))
    }

    @Test func accentsNeedBothAppearancesAndReadableText() throws {
        let checks = { (entry: ThemeJSON) in
            ThemeContributions(accents: [entry])
                .accents(
                    namespace: "acme", lightBackgrounds: self.lightBackgrounds, darkBackgrounds: self.darkBackgrounds)[
                    0]
        }
        let good = try checks(accentEntry(light: lightSwatch, dark: darkSwatch)).get()
        #expect(good.id == "acme/sea")
        #expect(good.light.accent == CodeColor(rgb: 0x2C5BA9))

        var faint = lightSwatch
        faint["text"] = "#9AB0D8"
        #expect("\(checks(accentEntry(light: faint, dark: darkSwatch)))".contains("too faint on Native's background"))
        var lowOnAccent = darkSwatch
        lowOnAccent["onAccent"] = "#FFFFFF"
        #expect("\(checks(accentEntry(light: lightSwatch, dark: lowOnAccent)))".contains("too faint on the accent"))
        #expect(
            "\(checks(.object(["id": .string("x"), "light": .object(lightSwatch.mapValues(ThemeJSON.string))])))"
                .contains("no \"dark\""))
    }

    @Test func manifestJSONDecodesWithoutValidating() throws {
        let json = #"{"code": [{"id": "a"}, 3], "accents": []}"#
        let decoded = try JSONDecoder().decode(ThemeContributions.self, from: Data(json.utf8))
        #expect(decoded.code.count == 2)
        #expect(try JSONDecoder().decode(ThemeContributions.self, from: Data("{}".utf8)).isEmpty)
    }
}
