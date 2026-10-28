import Testing

@testable import CodeThemes

@Suite struct ThemeTrialTests {
    private struct Backgrounds: Equatable, Sendable {
        var light = "paper"
        var dark = "standard"
    }

    private typealias Trial = ThemeTrial<Backgrounds>

    /// A plugin's theme, which can go away while the trial runs.
    private static let dusk = CodeTheme.nord.dark.map { CodeTheme(id: "lantern.dusk", name: "Dusk", dark: $0) }
    private static let lightThemes = CodeTheme.all.filter { $0.light != nil }
    private static let darkThemes = CodeTheme.all.filter { $0.dark != nil }

    private func trial(
        light: CodeTheme.ID = "native", dark: CodeTheme.ID = "native", mode: CodeAppearance = .dark,
        darkThemes: [CodeTheme] = darkThemes
    ) -> Trial {
        Trial(
            kept: .init(light: light, dark: dark, backgrounds: Backgrounds()), mode: mode,
            light: Self.lightThemes, dark: darkThemes)
    }

    @Test func keepWritesBothModesAndTheBackgrounds() {
        var trial = trial()
        trial.highlight(CodeTheme.tokyoNight.id)
        trial.mode = .light
        trial.highlight(CodeTheme.rosePine.id)
        trial.setBackgrounds(Backgrounds(light: "wool", dark: "trueBlack"))
        let written = trial.writes(.keep)
        #expect(written?.dark == CodeTheme.tokyoNight.id)
        #expect(written?.light == CodeTheme.rosePine.id)
        #expect(written?.backgrounds == Backgrounds(light: "wool", dark: "trueBlack"))
        // Keep with nothing changed still names both modes, so neither is left to a default.
        #expect(
            self.trial(light: "github", dark: "nord").writes(.keep)
                == .init(
                    light: "github", dark: "nord", backgrounds: Backgrounds()))
    }

    @Test func cancelWritesNothing() {
        var trial = trial()
        trial.highlight(CodeTheme.dracula.id)
        trial.setBackgrounds(Backgrounds(light: "wool", dark: "trueBlack"))
        #expect(trial.hasChanges)
        #expect(trial.writes(.cancel) == nil)
    }

    @Test func eachModeKeepsItsOwnHighlight() {
        var trial = trial(light: "github")
        #expect(trial.highlighted == .native)
        trial.highlight(CodeTheme.nord.id)
        trial.mode = .light
        #expect(trial.highlighted == .github)
        trial.mode = .dark
        #expect(trial.highlighted == .nord)
        #expect(trial.inUse(.dark) == .native)
    }

    @Test func arrowsStopAtTheEnds() {
        var trial = trial()
        trial.move(-1)
        #expect(trial.highlighted == Self.darkThemes.first)
        trial.move(1)
        #expect(trial.highlighted == Self.darkThemes[1])
        trial.move(100)
        #expect(trial.highlighted == Self.darkThemes.last)
    }

    @Test func typeSelectFindsTheFirstNameWithThePrefix() {
        var trial = trial()
        let found = trial.highlight(matching: "to")
        #expect(found)
        #expect(trial.highlighted == .tokyoNight)
        let missing = trial.highlight(matching: "zz")
        #expect(!missing)
        #expect(trial.highlighted == .tokyoNight)
    }

    @Test func aThemeForTheOtherModeOnlyIsNotOffered() {
        var trial = trial()
        trial.highlight(CodeTheme.catppuccinLatte.id)
        #expect(trial.highlighted == .native)
        #expect(!trial.hasChanges)
    }

    @Test func aPluginThemeThatDisappearsFallsBackToTheKeptOne() throws {
        let dusk = try #require(Self.dusk)
        var trial = trial(dark: "nord", darkThemes: Self.darkThemes + [dusk])
        trial.highlight(dusk.id)
        #expect(trial.highlighted == dusk)
        trial.update(light: Self.lightThemes, dark: Self.darkThemes)
        #expect(trial.highlighted == .nord)
        #expect(trial.writes(.keep)?.dark == CodeTheme.nord.id)
    }

    @Test func aKeptPluginThemeThatIsOffShowsNativeButSurvivesKeep() throws {
        let dusk = try #require(Self.dusk)
        var trial = trial(dark: dusk.id)
        #expect(trial.highlighted == .native)
        #expect(trial.inUse(.dark) == .native)
        trial.update(light: Self.lightThemes, dark: Self.darkThemes)
        #expect(trial.writes(.keep)?.dark == dusk.id)
        trial.update(light: Self.lightThemes, dark: Self.darkThemes + [dusk])
        #expect(trial.highlighted == dusk)
    }
}
