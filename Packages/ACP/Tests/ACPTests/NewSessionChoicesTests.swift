import Foundation
import Testing

@testable import ACP

/// What a new session starts on, against the options real adapters give a new session: codex-acp
/// 2.2.2 (`ConfigChoicesTests.loaded`, the same list `session/new` returns) and claude-agent-acp
/// 0.93.0 (`Wire.newSessionResult`).
struct NewSessionChoicesTests {
    static func codex() throws -> [ConfigOption] {
        try ConfigChoicesTests.options()
    }

    static func claude() throws -> [ConfigOption] {
        struct Result: Decodable { var configOptions: [ConfigOption] }
        return try JSONDecoder().decode(Result.self, from: Data(Wire.newSessionResult.utf8)).configOptions
    }

    static func option(_ id: String, in options: [ConfigOption]) throws -> ConfigOption {
        try #require(options.first { $0.id == id })
    }

    static func allowAll(_: ConfigOption, _: String) -> Bool { true }

    /// The user picked 6.1 Sol at Low effort with Fast mode on, in some earlier Codex task.
    static func lastPicked() throws -> ConfigChoices {
        let options = try codex()
        var picked = ConfigChoices()
        picked.choose(try option("model", in: options), value: "gpt-6.1-sol")
        picked.choose(try option("reasoning_effort", in: options), value: "low")
        picked.choose(try option("fast-mode", in: options), value: "on")
        return picked
    }

    @Test func startsOnWhatTheUserLastPicked() throws {
        let options = try Self.codex()
        let start = NewSessionChoices(lastUsed: try Self.lastPicked())

        // The model first, though the agent lists the mode first: it can change the efforts.
        #expect(start.order(in: options) == ["model", "reasoning_effort", "fast-mode"])
        #expect(
            start.start(of: "model", in: options, allows: Self.allowAll)
                == .set(try Self.option("model", in: options), value: "gpt-6.1-sol"))
        #expect(
            start.start(of: "reasoning_effort", in: options, allows: Self.allowAll)
                == .set(try Self.option("reasoning_effort", in: options), value: "low"))
        #expect(
            start.start(of: "fast-mode", in: options, allows: Self.allowAll)
                == .set(try Self.option("fast-mode", in: options), value: "on"))
    }

    /// A project's model and the user's defaults in Settings (or a launch argument) win over what
    /// was last picked; what they don't say still comes from the last pick.
    @Test func explicitDefaultsWinOverTheLastPick() throws {
        let options = try Self.codex()
        let start = NewSessionChoices(
            defaults: ["model": "gpt-6-sol", "thought_level": "high"], lastUsed: try Self.lastPicked())

        #expect(
            start.start(of: "model", in: options, allows: Self.allowAll)
                == .set(try Self.option("model", in: options), value: "gpt-6-sol"))
        #expect(
            start.start(of: "reasoning_effort", in: options, allows: Self.allowAll)
                == .set(try Self.option("reasoning_effort", in: options), value: "high"))
        #expect(
            start.start(of: "fast-mode", in: options, allows: Self.allowAll)
                == .set(try Self.option("fast-mode", in: options), value: "on"))
    }

    @Test func leavesTheAgentsValueWhenItAlreadyMatches() throws {
        let options = try Self.codex()
        // The adapter starts sessions on 6 Astra at Xhigh.
        var picked = ConfigChoices()
        picked.choose(try Self.option("model", in: options), value: "gpt-6-astra")
        let start = NewSessionChoices(defaults: ["thought_level": "xhigh"], lastUsed: picked)

        #expect(start.order(in: options).isEmpty)
        #expect(start.start(of: "model", in: options, allows: Self.allowAll) == nil)
    }

    /// The last-picked model is gone from the agent: the session says so once and keeps the agent's.
    @Test func saysWhenTheLastPickedModelIsGone() throws {
        let withoutSol = try ConfigChoicesTests.options(
            ConfigChoicesTests.loaded.replacingOccurrences(of: #"{"value":"gpt-6.1-sol","name":"6.1 Sol"},"#, with: ""))
        let start = NewSessionChoices(lastUsed: try Self.lastPicked())

        #expect(
            start.start(of: "model", in: withoutSol, allows: Self.allowAll)
                == .unavailable(
                    ConfigChoices.Choice(value: "gpt-6.1-sol", optionName: "Model", valueName: "6.1 Sol"),
                    kept: "6 Astra"))
    }

    /// Efforts and variants depend on the model, so one this model lacks is skipped without a word,
    /// and so is a default from Settings that the agent doesn't offer.
    @Test func skipsQuietlyWhatThisModelDoesntOffer() throws {
        let options = try Self.codex()
        var picked = ConfigChoices()
        let effort = try Self.option("reasoning_effort", in: options)
        picked.choose(effort, value: "minimal")
        let start = NewSessionChoices(defaults: ["model": "gpt-4"], lastUsed: picked)

        #expect(start.start(of: "reasoning_effort", in: options, allows: Self.allowAll) == nil)
        #expect(start.start(of: "model", in: options, allows: Self.allowAll) == nil)
    }

    @Test func policyWinsOverTheLastPick() throws {
        let options = try Self.codex()
        let start = NewSessionChoices(lastUsed: try Self.lastPicked())
        let noFastMode: (ConfigOption, String) -> Bool = { option, value in !(option.id == "fast-mode" && value == "on") }

        #expect(start.start(of: "fast-mode", in: options, allows: noFastMode) == nil)
    }

    /// Only the model and its variants are carried to new sessions; autonomy and Plan Mode belong
    /// to the task.
    @Test func remembersTheModelAndItsVariantsOnly() throws {
        let codex = try Self.codex()
        let claude = try Self.claude()

        for id in ["model", "reasoning_effort", "fast-mode"] {
            #expect(NewSessionChoices.remembers(try Self.option(id, in: codex)))
        }
        for id in ["model", "effort", "fast"] {
            #expect(NewSessionChoices.remembers(try Self.option(id, in: claude)))
        }
        #expect(!NewSessionChoices.remembers(try Self.option("mode", in: codex)))
        #expect(!NewSessionChoices.remembers(try Self.option("collaboration_mode", in: codex)))
        #expect(!NewSessionChoices.remembers(try Self.option("mode", in: claude)))
    }

    /// Claude Code names its effort option `effort`; the last pick goes by the option's id, so it
    /// lands on the agent it came from.
    @Test func startsAClaudeCodeSessionOnItsLastPick() throws {
        let options = try Self.claude()
        var picked = ConfigChoices()
        picked.choose(try Self.option("model", in: options), value: "claude-fable-5")
        picked.choose(try Self.option("effort", in: options), value: "medium")
        let start = NewSessionChoices(lastUsed: picked)

        #expect(start.order(in: options) == ["model", "effort"])
        #expect(
            start.start(of: "model", in: options, allows: Self.allowAll)
                == .set(try Self.option("model", in: options), value: "claude-fable-5"))
        #expect(
            start.start(of: "effort", in: options, allows: Self.allowAll)
                == .set(try Self.option("effort", in: options), value: "medium"))
    }
}
