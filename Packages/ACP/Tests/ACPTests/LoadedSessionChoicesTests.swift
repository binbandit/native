import Foundation
import Testing

@testable import ACP

struct LoadedSessionChoicesTests {
    @Test func savedThenConfiguredThenReported() throws {
        let options = try NewSessionChoicesTests.claude()
        let model = try NewSessionChoicesTests.option("model", in: options)
        let defaults = ["model": "claude-fable-5", "thought_level": "low"]
        let configured = ConfigChoices().fillingDefaults(defaults, in: options)
        #expect(configured.choices["model"]?.value == "claude-fable-5")
        #expect(configured.choices["effort"]?.value == "low")
        #expect(configured.restoreOrder(in: options).first == "model")
        #expect(
            configured.restoration(of: "model", in: options, allows: { _, _ in true })
                == .set(model, value: "claude-fable-5"))

        var saved = ConfigChoices()
        saved.choose(model, value: "opus")
        let resolved = saved.fillingDefaults(defaults, in: options)
        #expect(resolved.choices["model"]?.value == "opus")
        #expect(resolved.choices["effort"]?.value == "low")

        let unconfigured = ConfigChoices().fillingDefaults([:], in: options)
        #expect(unconfigured.isEmpty)
        #expect(unconfigured.preview(options, allows: { _, _ in true }) == options)
    }

    @Test func unavailableSavedChoiceStillWinsOverSettings() throws {
        let options = try NewSessionChoicesTests.codex()
        var saved = ConfigChoices()
        saved.choose(try NewSessionChoicesTests.option("model", in: options), value: "retired-model")
        let resolved = saved.fillingDefaults(["model": "gpt-6.1-sol"], in: options)
        #expect(resolved == saved)
    }

    @Test func settingsFollowCategoriesAndSkipUnavailableValues() throws {
        let options = try NewSessionChoicesTests.codex()
        let resolved = ConfigChoices().fillingDefaults(
            ["model": "gpt-6.1-sol", "thought_level": "low"], in: options)
        #expect(resolved.choices["model"]?.value == "gpt-6.1-sol")
        #expect(resolved.choices["reasoning_effort"]?.value == "low")
        #expect(resolved.choices["mode"] == nil)
        #expect(ConfigChoices().fillingDefaults(["model": "retired-model"], in: options).isEmpty)
        #expect(ConfigChoices().fillingDefaults(["model": ""], in: options).isEmpty)
    }

    @Test func effortIsResolvedAgainAfterTheModelChanges() throws {
        let options = try NewSessionChoicesTests.codex()
        let defaults = ["model": "gpt-6.1-sol", "thought_level": "low"]
        let withoutEffort = options.filter { $0.category != "thought_level" }
        let before = ConfigChoices().fillingDefaults(defaults, in: withoutEffort)
        #expect(before.restoreOrder(in: withoutEffort) == ["model"])
        let after = ConfigChoices().fillingDefaults(defaults, in: options)
        #expect(after.restoreOrder(in: options) == ["model", "reasoning_effort"])
    }

    @Test func matchingReportedValueIsStillRemembered() throws {
        let options = try NewSessionChoicesTests.codex()
        let resolved = ConfigChoices().fillingDefaults(["model": "gpt-6-astra"], in: options)
        #expect(resolved.choices["model"]?.value == "gpt-6-astra")
        #expect(resolved.restoration(of: "model", in: options, allows: { _, _ in true }) == nil)
    }
}
