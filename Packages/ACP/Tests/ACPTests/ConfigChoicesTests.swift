import Foundation
import Testing

@testable import ACP

/// Deciding what to set back when a session is reopened, against real codex-acp 2.2.2 traffic: a
/// session switched to 6.1 Sol, closed (`session/close`) and loaded again comes back on the
/// adapter's default model and mode.
struct ConfigChoicesTests {
    /// The `configOptions` of codex-acp 2.2.2's `session/load` result for that session (captured
    /// 2026-10-18), descriptions trimmed. Mode is listed before the model.
    static let loaded = #"""
        [
          {"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"agent","options":[
            {"value":"read-only","name":"Read-only"},{"value":"workspace-write","name":"Workspace access"},
            {"value":"agent","name":"Auto review"},{"value":"agent-full-access","name":"Full access"}]},
          {"id":"collaboration_mode","name":"Collaboration mode","category":"collaboration_mode","type":"select","currentValue":"default","options":[
            {"value":"default","name":"Default"},{"value":"plan","name":"Plan"}]},
          {"id":"model","name":"Model","category":"model","type":"select","currentValue":"gpt-6-astra","options":[
            {"value":"gpt-6.1-sol","name":"6.1 Sol"},{"value":"gpt-6-astra","name":"6 Astra"},{"value":"gpt-6-sol","name":"6 Sol"},
            {"value":"gpt-6-luna","name":"6 Luna"},{"value":"gpt-5.6-sol","name":"5.6 Sol"}]},
          {"id":"reasoning_effort","name":"Reasoning effort","category":"thought_level","type":"select","currentValue":"xhigh","options":[
            {"value":"low","name":"Low"},{"value":"medium","name":"Medium"},{"value":"high","name":"High"},
            {"value":"xhigh","name":"Xhigh"},{"value":"max","name":"Max"},{"value":"ultra","name":"Ultra"}]},
          {"id":"fast-mode","name":"Fast mode","category":"model_config","type":"select","currentValue":"off","options":[
            {"value":"off","name":"Off"},{"value":"on","name":"On"}]}
        ]
        """#

    static func options(_ json: String = loaded) throws -> [ConfigOption] {
        try JSONDecoder().decode([ConfigOption].self, from: Data(json.utf8))
    }

    static func option(_ id: String, in options: [ConfigOption]) throws -> ConfigOption {
        try #require(options.first { $0.id == id })
    }

    static func allowAll(_: ConfigOption, _: String) -> Bool { true }

    /// The model and mode the session ran with, chosen in the composer.
    static func chosen() throws -> ConfigChoices {
        let options = try options()
        var choices = ConfigChoices()
        choices.choose(try option("mode", in: options), value: "agent-full-access")
        choices.choose(try option("model", in: options), value: "gpt-6.1-sol")
        return choices
    }

    @Test func setsBackWhatTheAgentReopenedOnItsDefaults() throws {
        let options = try Self.options()
        let choices = try Self.chosen()

        // The model goes first, though the agent lists the mode first: changing it can change efforts.
        #expect(choices.restoreOrder(in: options) == ["model", "mode"])
        #expect(
            choices.restoration(of: "model", in: options, allows: Self.allowAll)
                == .set(try Self.option("model", in: options), value: "gpt-6.1-sol"))
        #expect(
            choices.restoration(of: "mode", in: options, allows: Self.allowAll)
                == .set(try Self.option("mode", in: options), value: "agent-full-access"))
    }

    @Test func leavesAloneWhatTheUserNeverChanged() throws {
        let options = try Self.options()
        let choices = try Self.chosen()

        #expect(!choices.restoreOrder(in: options).contains("reasoning_effort"))
        #expect(choices.restoration(of: "reasoning_effort", in: options, allows: Self.allowAll) == nil)
    }

    @Test func doesNothingWhenTheAgentRestoredItItself() throws {
        let restored = try Self.options(
            Self.loaded.replacingOccurrences(
                of: #""currentValue":"gpt-6-astra""#, with: #""currentValue":"gpt-6.1-sol""#))

        #expect(try Self.chosen().restoration(of: "model", in: restored, allows: Self.allowAll) == nil)
    }

    @Test func keepsTheAgentsValueWhenTheChosenOneIsGone() throws {
        // The adapter stopped offering 6.1 Sol.
        let withoutSol = try Self.options(
            Self.loaded.replacingOccurrences(of: #"{"value":"gpt-6.1-sol","name":"6.1 Sol"},"#, with: ""))
        let choices = try Self.chosen()
        let sol = ConfigChoices.Choice(value: "gpt-6.1-sol", optionName: "Model", valueName: "6.1 Sol")

        #expect(
            choices.restoration(of: "model", in: withoutSol, allows: Self.allowAll)
                == .unavailable(sol, kept: "6 Astra"))
    }

    @Test func reportsAnOptionTheAgentNoLongerHas() throws {
        let options = try Self.options()
        var choices = try Self.chosen()
        choices.choose(try Self.option("fast-mode", in: options), value: "on")
        let withoutFastMode = options.filter { $0.id != "fast-mode" }

        // Still restored, last, so it can say so.
        #expect(choices.restoreOrder(in: withoutFastMode) == ["model", "mode", "fast-mode"])
        #expect(
            choices.restoration(of: "fast-mode", in: withoutFastMode, allows: Self.allowAll)
                == .unavailable(ConfigChoices.Choice(value: "on", optionName: "Fast mode", valueName: "On"), kept: nil))
    }

    /// Some agents report their options only after answering `session/load`, or not at all.
    @Test func restoresNothingWhenTheAgentListsNoOptions() throws {
        #expect(try Self.chosen().restoreOrder(in: []).isEmpty)
    }

    @Test func policyWinsOverTheChoice() throws {
        let options = try Self.options()
        let noFullAccess: (ConfigOption, String) -> Bool = { option, value in
            !(option.category == "mode" && value == "agent-full-access")
        }

        #expect(
            try Self.chosen().restoration(of: "mode", in: options, allows: noFullAccess)
                == .forbidden(
                    ConfigChoices.Choice(value: "agent-full-access", optionName: "Mode", valueName: "Full access")))
    }

    /// A user's later choice, or the agent's own change, is what a reopened session goes back to,
    /// so restoring never undoes either.
    @Test func followsLaterChangesToChosenOptionsOnly() throws {
        var choices = try Self.chosen()
        // The live session, on what was chosen.
        var state = SessionState()
        state.apply(
            .configOptions(
                try Self.options(
                    Self.loaded
                        .replacingOccurrences(
                            of: #""currentValue":"gpt-6-astra""#, with: #""currentValue":"gpt-6.1-sol""#
                        )
                        .replacingOccurrences(
                            of: #""currentValue":"agent""#, with: #""currentValue":"agent-full-access""#))))
        // The agent drops to Read-only itself, and the effort changes, which nobody chose before.
        state.apply(.currentMode("read-only"))
        let effort = try #require(state.configOptions.firstIndex { $0.id == "reasoning_effort" })
        state.configOptions[effort].kind = .select(
            currentValue: "low", options: state.configOptions[effort].selectOptions)

        let changed = choices.follow(state.configOptions)
        #expect(changed)
        #expect(choices.choices["mode"]?.value == "read-only")
        #expect(choices.choices["model"]?.value == "gpt-6.1-sol")
        #expect(choices.choices["reasoning_effort"] == nil)
        let changedAgain = choices.follow(state.configOptions)
        #expect(!changedAgain)

        // Reopened on the defaults, the session goes back to Read-only, not to Full access.
        let reopened = try Self.options()
        #expect(
            choices.restoration(of: "mode", in: reopened, allows: Self.allowAll)
                == .set(try Self.option("mode", in: reopened), value: "read-only"))
    }

    /// While the session loads, it shows what restoring will set, so the agent's defaults never
    /// flash up first; a value that can't come back shows as the agent's.
    @Test func previewsTheSessionAsRestoringLeavesIt() throws {
        let options = try Self.options()
        var choices = try Self.chosen()
        choices.choose(try Self.option("fast-mode", in: options), value: "on")
        choices.choose(try Self.option("reasoning_effort", in: options), value: "minimal")
        let noFastMode: (ConfigOption, String) -> Bool = { option, value in !(option.id == "fast-mode" && value == "on")
        }

        let shown = choices.preview(options, allows: noFastMode)

        let current = Dictionary(uniqueKeysWithValues: shown.map { ($0.id, $0.currentValue) })
        #expect(current["model"] == "gpt-6.1-sol")
        #expect(current["mode"] == "agent-full-access")
        // Not offered, and forbidden: both stay the agent's.
        #expect(current["reasoning_effort"] == "xhigh")
        #expect(current["fast-mode"] == "off")
        #expect(shown.map(\.id) == options.map(\.id))
        #expect(ConfigChoices().preview(options, allows: Self.allowAll) == options)
    }

    @Test func survivesBeingSaved() throws {
        let choices = try Self.chosen()
        let saved = try JSONEncoder().encode(choices)

        #expect(try JSONDecoder().decode(ConfigChoices.self, from: saved) == choices)
    }
}

extension ConfigOption {
    fileprivate var selectOptions: [SelectOption] {
        if case .select(_, let options) = kind { options } else { [] }
    }

    fileprivate var currentValue: String? {
        if case .select(let current, _) = kind { current } else { nil }
    }
}
