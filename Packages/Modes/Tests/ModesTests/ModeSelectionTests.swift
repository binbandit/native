import ACP
import Foundation
import Testing

@testable import Modes

struct ModeSelectionTests {
    /// Switching runs the changes against the options, as the agent would report them back.
    private func switching(
        _ selection: ModeSelection, to mode: Mode, on options: [ConfigOption]
    ) -> (ModeSelection, [ConfigOption], [ModeResolution.Change]) {
        let (changes, next) = selection.switching(
            to: mode.id, ModeResolver.resolve(mode, options: options), options: options)
        return (next, Fixtures.applying(changes, to: options), changes)
    }

    @Test func planAndBackRestoresTheAutonomyLevel() throws {
        let start = try Fixtures.options(Fixtures.claudeCode)
        let (planning, inPlan, toPlan) = switching(ModeSelection(), to: .plan, on: start)
        #expect(toPlan == [.init(optionID: "mode", value: "plan")])
        #expect(planning.effectiveMode(options: inPlan) == .plan)
        let (building, back, toBuild) = switching(planning, to: .build, on: inPlan)
        #expect(toBuild == [.init(optionID: "mode", value: "acceptEdits")])
        #expect(Fixtures.current("mode", in: back) == "acceptEdits")
        #expect(building.restore.isEmpty)
    }

    /// Ask then Review: both read-only, so nothing changes between them, and Build still goes back
    /// to the level from before either.
    @Test func modesChainBackToTheOriginalLevel() throws {
        let start = try Fixtures.options(Fixtures.codex)
        let (asking, readOnly, _) = switching(ModeSelection(), to: .ask, on: start)
        let (reviewing, stillReadOnly, toReview) = switching(asking, to: .review, on: readOnly)
        #expect(toReview.isEmpty)
        let (_, back, toBuild) = switching(reviewing, to: .build, on: stillReadOnly)
        #expect(toBuild == [.init(optionID: "mode", value: "agent")])
        #expect(Fixtures.current("mode", in: back) == "agent")
    }

    /// The user (or the agent) moved the setting since the mode set it: leaving keeps their choice.
    @Test func leavingNeverUndoesALaterChange() throws {
        let start = try Fixtures.options(Fixtures.codex)
        let (asking, readOnly, _) = switching(ModeSelection(), to: .ask, on: start)
        let changedByHand = Fixtures.setting(readOnly, "mode", to: "workspace-write")
        let (_, _, toBuild) = switching(asking, to: .build, on: changedByHand)
        #expect(toBuild.isEmpty)
    }

    /// The agent left the plan mode Plan turned on (a plan was approved): the task builds again.
    @Test func agentLeavingPlanModeMeansBuild() throws {
        let start = try Fixtures.options(Fixtures.claudeCode)
        let (planning, _, _) = switching(ModeSelection(), to: .plan, on: start)
        let approved = Fixtures.setting(start, "mode", to: "acceptEdits")
        #expect(planning.effectiveMode(options: approved) == .build)
        // Ask on Claude Code rides on plan mode too.
        let (asking, _, _) = switching(ModeSelection(), to: .ask, on: start)
        #expect(asking.effectiveMode(options: approved) == .build)
    }

    @Test func agentTurningPlanModeOnItselfMeansPlan() throws {
        let start = try Fixtures.options(Fixtures.codex)
        let (debugging, options, _) = switching(ModeSelection(), to: .debug, on: start)
        #expect(debugging.effectiveMode(options: options) == .debug)
        let planning = Fixtures.setting(options, "collaboration_mode", to: "plan")
        #expect(debugging.effectiveMode(options: planning) == .plan)
    }

    /// Picking Plan while the agent is already planning still leaves something to go back to.
    @Test func planPickedWhilePlanModeIsOn() throws {
        let start = Fixtures.setting(try Fixtures.options(Fixtures.claudeCode), "mode", to: "plan")
        let (planning, inPlan, toPlan) = switching(ModeSelection(), to: .plan, on: start)
        #expect(toPlan.isEmpty)
        let approved = Fixtures.setting(inPlan, "mode", to: "acceptEdits")
        #expect(planning.effectiveMode(options: approved) == .build)
        let (_, _, toBuild) = switching(planning, to: .build, on: inPlan)
        #expect(toBuild == [.init(optionID: "mode", value: "default")])
    }

    @Test func theModelChangesFirst() throws {
        let fast = Mode(
            id: .custom("fast"), name: "Fast", symbol: "hare", summary: "", instructions: "Go.",
            settings: ModeSettings(autonomy: .full, model: "gpt-6.1-sol"), source: .custom)
        let (_, _, changes) = switching(ModeSelection(), to: fast, on: try Fixtures.options(Fixtures.codex))
        #expect(changes.map(\.optionID) == ["model", "mode"])
    }

    @Test(arguments: [Mode.ask, .review, .plan])
    func continuingMovesPlanOwnershipToTheTargetsOption(mode: Mode) throws {
        let (asking, _, _) = switching(ModeSelection(), to: mode, on: try Fixtures.options(Fixtures.claudeCode))
        let target = Fixtures.setting(try Fixtures.options(Fixtures.codex), "collaboration_mode", to: "plan")
        let continued = asking.continuing(options: target)
        #expect(continued.effectiveMode(options: target) == mode.id)
        #expect(continued.restore["mode"] == nil)
        let (_, _, changes) = switching(continued, to: .build, on: target)
        #expect(changes == [.init(optionID: "collaboration_mode", value: "default")])
    }

    @Test func continuingDoesNotMistakeAnUnsupportedPlanForApproval() throws {
        let (asking, _, _) = switching(ModeSelection(), to: .ask, on: try Fixtures.options(Fixtures.claudeCode))
        let target = try Fixtures.options(Fixtures.claudeCode)
        #expect(asking.continuing(options: target).effectiveMode(options: target) == .ask)
    }

    @Test func continuingDoesNotRestoreAnUnsafeFirstChoice() throws {
        let options = try Fixtures.options(
            #"[{"id":"mode","name":"Permissions","category":"mode","type":"select","currentValue":"plan","options":[{"value":"bypassPermissions","name":"Full"},{"value":"default","name":"Ask"},{"value":"plan","name":"Plan"}]}]"#
        )
        let continued = ModeSelection(mode: .ask).continuing(options: options)
        #expect(continued.restore["mode"]?.original == "default")
    }

    @Test func survivesBeingSaved() throws {
        let (asking, _, _) = switching(ModeSelection(), to: .ask, on: try Fixtures.options(Fixtures.codex))
        let data = try JSONEncoder().encode(asking)
        #expect(try JSONDecoder().decode(ModeSelection.self, from: data) == asking)
    }
}
