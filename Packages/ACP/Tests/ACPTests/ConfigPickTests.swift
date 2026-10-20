import Foundation
import Testing

@testable import ACP

/// What the composer does with a pick: stepping the effort meter, and whether a pick becomes what
/// the agent's new sessions start on. Against codex-acp 2.2.2's options (`ConfigChoicesTests.loaded`).
struct ConfigPickTests {
    /// codex-acp's effort option, on `current`.
    static func effort(_ current: String) throws -> ConfigOption {
        let json = ConfigChoicesTests.loaded.replacingOccurrences(
            of: #""currentValue":"xhigh""#, with: #""currentValue":"\#(current)""#)
        return try ConfigChoicesTests.option("reasoning_effort", in: ConfigChoicesTests.options(json))
    }

    @Test func stepsToTheNextLevelAndWrapsAround() throws {
        #expect(try Self.effort("xhigh").valueAfterCurrent == "max")
        #expect(try Self.effort("ultra").valueAfterCurrent == "low")
    }

    /// A session reloading after the host restarted can report a value the list doesn't have; a
    /// press then must not land on Low.
    @Test func neverStepsFromAValueItCannotPlace() throws {
        #expect(try Self.effort("minimal").valueAfterCurrent == nil)
        var empty = try Self.effort("xhigh")
        empty.kind = .select(currentValue: "xhigh", options: [])
        #expect(empty.valueAfterCurrent == nil)
    }

    @Test func aPickTheAgentTookIsRemembered() throws {
        let shown = try Self.effort("xhigh")
        #expect(
            NewSessionChoices.remembersPick(
                "max", from: shown, agentHad: shown, agentHas: try Self.effort("max"), settled: true))
    }

    /// While the session gets its settings back, the composer shows those it's about to get, not
    /// the agent's: a pick then is about this session only.
    @Test func aPickWhileTheSessionSettlesIsNotRemembered() throws {
        let shown = try Self.effort("xhigh")
        #expect(
            !NewSessionChoices.remembersPick(
                "max", from: shown, agentHad: shown, agentHas: try Self.effort("max"), settled: false))
        // The composer previews the chosen Xhigh while the agent still reports its default.
        #expect(
            !NewSessionChoices.remembersPick(
                "max", from: shown, agentHad: try Self.effort("low"), agentHas: try Self.effort("max"), settled: true))
    }

    @Test func aPickFromAListTheAgentDoesNotReportIsNotRemembered() throws {
        let shown = try Self.effort("xhigh")
        #expect(
            !NewSessionChoices.remembersPick(
                "max", from: shown, agentHad: nil, agentHas: try Self.effort("max"), settled: true))
    }

    @Test func aPickTheAgentDidNotTakeIsNotRemembered() throws {
        let shown = try Self.effort("xhigh")
        #expect(
            !NewSessionChoices.remembersPick(
                "max", from: shown, agentHad: shown, agentHas: try Self.effort("xhigh"), settled: true))
    }

    /// Autonomy and Plan Mode belong to the task they were picked in.
    @Test func onlyTheModelAndItsVariantsAreRemembered() throws {
        let mode = try ConfigChoicesTests.option("mode", in: ConfigChoicesTests.options())
        var full = mode
        full.kind = .select(currentValue: "agent-full-access", options: [])
        #expect(
            !NewSessionChoices.remembersPick(
                "agent-full-access", from: mode, agentHad: mode, agentHas: full, settled: true))
    }
}
