import ACP
import Testing

@testable import Modes

struct ModeInstructionsTests {
    private func preamble(_ mode: Mode, after delivered: PromptPreamble.Marker?, json: String = Fixtures.codex) throws
        -> PromptPreamble?
    {
        ModeInstructions.preamble(
            for: mode, ModeResolver.resolve(mode, options: try Fixtures.options(json)), delivered: delivered)
    }

    @Test func buildSaysNothingUntilAnotherModeHasSpoken() throws {
        #expect(try preamble(.build, after: nil) == nil)
    }

    @Test func aModeSpeaksOnceThenStaysQuiet() throws {
        let debug = try #require(try preamble(.debug, after: nil))
        #expect(debug.marker.label == "Debug mode")
        #expect(debug.marker.symbol == "ladybug")
        #expect(ModeInstructions.mode(of: debug.marker) == .debug)
        #expect(debug.instructions.hasPrefix("The user put this task in Debug mode in Native. Work this way"))
        #expect(debug.instructions.contains("Reproduce it first"))
        #expect(try preamble(.debug, after: debug.marker) == nil)
        // It survives the trip through a prompt and back.
        #expect(PromptPreamble(framed: debug.framed) == debug)
    }

    @Test func switchingSaysWhatItReplaces() throws {
        let ask = try #require(try preamble(.ask, after: nil))
        let review = try #require(try preamble(.review, after: ask.marker))
        #expect(review.instructions.hasPrefix("The user put this task in Review mode in Native, in place of Ask mode."))
    }

    @Test func backToBuildSaysTheEarlierInstructionsAreOver() throws {
        let debug = try #require(try preamble(.debug, after: nil))
        let build = try #require(try preamble(.build, after: debug.marker))
        #expect(build.marker.id == "build")
        #expect(build.instructions.contains("the instructions from Debug mode no longer apply"))
        #expect(try preamble(.build, after: build.marker) == nil)
    }

    /// A mode whose instructions were edited after they went out sends them again.
    @Test func editedInstructionsGoOutAgain() throws {
        var mine = Mode(
            id: .custom("terse"), name: "Terse", symbol: "text.word.spacing", summary: "", instructions: "Be brief.",
            source: .custom)
        let first = try #require(try preamble(mine, after: nil))
        #expect(try preamble(mine, after: first.marker) == nil)
        mine.instructions = "Be very brief."
        #expect(try preamble(mine, after: first.marker) != nil)
    }

    @Test func planDefersToTheAgentsPlanMode() throws {
        let plan = try #require(try preamble(.plan, after: nil))
        #expect(plan.instructions.contains(Mode.agentPlanInstructions))
        #expect(!plan.instructions.contains("Reply with a plan"))
        let withoutPlanMode = try #require(try preamble(.plan, after: nil, json: Fixtures.unknown))
        #expect(withoutPlanMode.instructions.contains("Reply with a plan"))
        #expect(withoutPlanMode.instructions.contains("Native couldn't make your permissions read-only"))
    }
}
