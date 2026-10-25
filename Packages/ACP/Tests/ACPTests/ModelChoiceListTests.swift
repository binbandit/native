import Foundation
import Testing

@testable import ACP

/// The settings popover's model rows, against real lists: Claude Code with a gateway's 59 models
/// (`GatewayWire`), Claude Code without one (`Wire.newSessionResult`) and codex-acp 2.2.2
/// (`ConfigChoicesTests.loaded`).
struct ModelChoiceListTests {
    static func models(_ options: [ConfigOption]) throws -> (current: String, choices: [ConfigOption.SelectOption]) {
        let option = try #require(options.first { $0.category == "model" })
        guard case .select(let current, let choices) = option.kind else {
            Issue.record("The model option isn't a select")
            return ("", [])
        }
        return (current, choices)
    }

    static func gateway() throws -> (current: String, choices: [ConfigOption.SelectOption]) {
        try models(GatewayWire.options())
    }

    static func names(_ list: ModelChoiceList) -> [String] {
        list.rows.map(\.name)
    }

    /// Every name and value arrives as sent: Native neither reverses, reorders nor re-pairs them,
    /// and no bidirectional control character hides in either.
    @Test func keepsTheGatewaysNamesAndValuesAsSent() throws {
        let (_, choices) = try Self.gateway()
        #expect(choices.count == 59)
        let haiku = try #require(choices.first { $0.name == "Claude Haiku 4.5" })
        #expect(haiku.value == "claude-fable-5-dd-5.4-ukiah-edualc/tolipoc")
        #expect(choices.first { $0.value == "haiku" }?.name == "Haiku 5.5")

        let controls = Set(
            [0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
                .compactMap(Unicode.Scalar.init))
        for choice in choices {
            let text = choice.name + choice.value + (choice.description ?? "")
            #expect(text.unicodeScalars.allSatisfy { !controls.contains($0) })
        }
    }

    @Test func showsAShortListWholeWithoutValues() throws {
        let (current, choices) = try Self.models(ConfigChoicesTests.options())
        let list = ModelChoiceList(choices: choices, current: current)
        #expect(!list.isFilterable)
        #expect(Self.names(list) == ["6.1 Sol", "6 Astra", "6 Sol", "6 Luna", "5.6 Sol"])
        #expect(list.rows.allSatisfy { $0.detail == nil })
    }

    /// Default says what it runs now; "(recommended)" is the agent's aside, not part of the name.
    @Test func saysWhatDefaultRuns() throws {
        let (current, choices) = try Self.models(NewSessionChoicesTests.claude())
        let list = ModelChoiceList(choices: choices, current: current)
        #expect(list.rows.first?.name == "Default")
        #expect(list.rows.first?.detail == .note("Opus"))
        #expect(list.rows.dropFirst().allSatisfy { $0.detail == nil })
    }

    /// Past eight models, six slots: the agent's first six, with the current model in the last one
    /// when it would otherwise be out of view (Haiku 5.5 is the 47th of the gateway's list).
    @Test func keepsTheCurrentModelInView() throws {
        let (_, choices) = try Self.gateway()
        let list = ModelChoiceList(choices: choices, current: "haiku")
        #expect(list.isFilterable)
        #expect(
            Self.names(list) == [
                "Default", "Opus 5.5", "Claude Fable 5", "Claude Fable 5.1", "Claude Haiku 4.5", "Haiku 5.5",
            ])
        #expect(list.overflow == 0)
        #expect(ModelChoiceList(choices: choices, current: "opus").rows.last?.name == "Codex Auto Review")
    }

    /// The filter matches names, then values, never descriptions: "gateway" is in every gateway
    /// row's description and in none of their names or values.
    @Test func filtersOnNamesAndValuesNotDescriptions() throws {
        let (_, choices) = try Self.gateway()
        #expect(ModelChoiceList(choices: choices, current: "haiku", query: "gateway").rows.isEmpty)

        let haiku = ModelChoiceList(choices: choices, current: "haiku", query: "haiku")
        #expect(
            Self.names(haiku) == ["Claude Haiku 4.5", "Haiku 5.5", "Claude 3.5 Haiku", "Claude 4.5 Haiku"])
        let first = try #require(haiku.rows.first)
        #expect(first.nameMatches.map { String(first.name[$0]) } == ["Haiku"])

        // Only a value says this; the row shows that value, with the match.
        let reversed = ModelChoiceList(choices: choices, current: "haiku", query: "otua-xedoc")
        let row = try #require(reversed.rows.first)
        #expect(row.name == "Codex Auto Review")
        guard case .value(let value, let matches) = row.detail else {
            Issue.record("Expected the value as the detail")
            return
        }
        #expect(matches.map { String(value[$0]) } == ["otua-xedoc"])
    }

    /// More matches than slots: five rows, and the sixth slot says how many more.
    @Test func saysHowManyMoreMatch() throws {
        let (_, choices) = try Self.gateway()
        let list = ModelChoiceList(choices: choices, current: "haiku", query: "gpt")
        #expect(list.rows.count == 5)
        #expect(list.overflow == 26)
    }

    /// Rows that share a name say what sets them apart: a short description no other has, else the
    /// value (the gateway's "GPT-4o" rows all say "From gateway").
    @Test func tellsSameNamedRowsApart() throws {
        let (_, choices) = try Self.gateway()
        let list = ModelChoiceList(choices: choices, current: "haiku", query: "gpt-4o mini")
        #expect(
            list.rows.map(\.detail) == [
                .value("claude-fable-5-dd-81-70-4202-inim-o4-tpg/tolipoc", matches: []),
                .value("claude-fable-5-dd-inim-o4-tpg/tolipoc", matches: []),
            ])

        let sonnets = [
            ConfigOption.SelectOption(value: "sonnet", name: "Sonnet 5.5", description: nil),
            ConfigOption.SelectOption(value: "sonnet[1m]", name: "Sonnet 5.5", description: "1M context"),
        ]
        #expect(ModelChoiceList(choices: sonnets, current: "sonnet").rows.map(\.detail) == [nil, .note("1M context")])
    }

    /// A repeated value is one row: the first, since the value is what Native sends back.
    @Test func keepsTheFirstOfARepeatedValue() throws {
        let choices = [
            ConfigOption.SelectOption(value: "gpt-6-sol", name: "6 Sol", description: nil),
            ConfigOption.SelectOption(value: "gpt-6-sol", name: "6 Sol (gateway)", description: nil),
            ConfigOption.SelectOption(value: "gpt-6-luna", name: "6 Luna", description: nil),
        ]
        #expect(choices.uniqued.map(\.name) == ["6 Sol", "6 Luna"])
        #expect(ModelChoiceList(choices: choices, current: "gpt-6-sol").rows.map(\.id) == ["gpt-6-sol", "gpt-6-luna"])
    }

    @Test func readsTheModelsPurpose() throws {
        let (_, choices) = try Self.gateway()
        let haiku = try #require(choices.first { $0.value == "haiku" })
        #expect(haiku.purpose?.hasPrefix("Fastest for quick answers · ") == true)
        #expect(choices[0].purpose == "Opus")
        #expect(choices[2].purpose == "From gateway")
    }
}
