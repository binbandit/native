import ACP
import Testing

@testable import Modes

struct ModeResolverTests {
    @Test func askIsReadOnlyOnCodex() throws {
        let resolution = ModeResolver.resolve(.ask, options: try Fixtures.options(Fixtures.codex))
        #expect(resolution.changes == [.init(optionID: "mode", value: "read-only")])
        #expect(resolution.limits.isEmpty)
        #expect(!resolution.isReadOnlyUnenforced)
    }

    /// Claude Code has no read-only level; its plan mode, which changes nothing, stands in.
    @Test func askUsesPlanModeOnClaudeCode() throws {
        let resolution = ModeResolver.resolve(.ask, options: try Fixtures.options(Fixtures.claudeCode))
        #expect(resolution.changes == [.init(optionID: "mode", value: "plan")])
        #expect(resolution.limits == [.readOnlyViaPlanMode])
        #expect(resolution.usesAgentPlanMode)
        #expect(!resolution.isReadOnlyUnenforced)
    }

    @Test func planUsesTheAgentsOwnPlanMode() throws {
        let codex = ModeResolver.resolve(.plan, options: try Fixtures.options(Fixtures.codex))
        #expect(codex.changes == [.init(optionID: "collaboration_mode", value: "plan")])
        #expect(codex.usesAgentPlanMode)
        let claude = ModeResolver.resolve(.plan, options: try Fixtures.options(Fixtures.claudeCode))
        #expect(claude.changes == [.init(optionID: "mode", value: "plan")])
        #expect(claude.limits.isEmpty)
    }

    /// Without a plan mode or a read-only level, Plan takes the most careful level and says what it
    /// can't enforce.
    @Test func planOnAnAgentWithoutOne() throws {
        let resolution = ModeResolver.resolve(.plan, options: try Fixtures.options(Fixtures.unknown))
        #expect(resolution.changes == [.init(optionID: "approvals", value: "careful")])
        #expect(resolution.limits == [.noPlanMode, .readOnlyAsks(level: "Careful")])
        #expect(resolution.isReadOnlyUnenforced)
        #expect(!resolution.usesAgentPlanMode)
    }

    @Test func noPermissionModesLeavesItToTheInstructions() {
        let resolution = ModeResolver.resolve(.review, options: [])
        #expect(resolution.changes.isEmpty)
        #expect(resolution.limits == [.readOnlyUnenforced])
        #expect(resolution.isReadOnlyUnenforced)
    }

    @Test func debugAndBuildChangeNothing() throws {
        for mode in [Mode.build, .debug] {
            let resolution = ModeResolver.resolve(mode, options: try Fixtures.options(Fixtures.codex))
            #expect(resolution.changes.isEmpty)
            #expect(resolution.limits.isEmpty)
        }
    }

    /// Policy wins: a forbidden read-only level gives way to the next most careful one, and says so.
    @Test func forbiddenReadOnlyFallsBackToTheNearestAllowed() throws {
        let resolution = ModeResolver.resolve(.ask, options: try Fixtures.options(Fixtures.codex)) { _, value in
            value != "read-only"
        }
        #expect(resolution.changes == [.init(optionID: "mode", value: "workspace-write")])
        #expect(resolution.limits == [.forbidden(wanted: "Read-only", using: "Workspace access")])
        #expect(resolution.limits.allSatisfy(\.isPolicy))
    }

    @Test func forbiddenLevelFallsBackToTheNearestAllowed() throws {
        let fast = custom(ModeSettings(autonomy: .full))
        let options = try Fixtures.options(Fixtures.codex)
        #expect(ModeResolver.resolve(fast, options: options).changes == [.init(optionID: "mode", value: "agent-full-access")])
        let resolution = ModeResolver.resolve(fast, options: options) { _, value in value != "agent-full-access" }
        #expect(resolution.changes == [.init(optionID: "mode", value: "agent")])
        #expect(resolution.limits == [.forbidden(wanted: "Full access", using: "Auto review")])
    }

    @Test func forbiddenPlanModeKeepsTheAgentReadOnlyInstead() throws {
        let resolution = ModeResolver.resolve(.plan, options: try Fixtures.options(Fixtures.codex)) { option, _ in
            option.id != "collaboration_mode"
        }
        #expect(resolution.changes == [.init(optionID: "mode", value: "read-only")])
        #expect(resolution.limits == [.forbidden(wanted: "Plan Mode", using: nil)])
    }

    /// Claude Code's Don't ask refuses what isn't allowed rather than sitting on the scale, so a
    /// mode never lands on it.
    @Test func levelsOffTheScaleAreNeverPicked() throws {
        let options = try Fixtures.options(Fixtures.claudeCode)
        let levels = ModeAutonomy.allCases.filter { $0 != .readOnly }.map {
            ModeResolver.resolve(custom(ModeSettings(autonomy: $0)), options: options).changes.first?.value
        }
        #expect(levels == ["default", "acceptEdits", "auto", "bypassPermissions"])
    }

    @Test func modelAndEffortByValueOrName() throws {
        let options = try Fixtures.options(Fixtures.codex)
        let resolution = ModeResolver.resolve(custom(ModeSettings(model: "6.1 sol", effort: "high")), options: options)
        #expect(
            resolution.changes == [
                .init(optionID: "model", value: "gpt-6.1-sol"), .init(optionID: "reasoning_effort", value: "high"),
            ])
        let missing = ModeResolver.resolve(custom(ModeSettings(model: "opus")), options: options)
        #expect(missing.changes.isEmpty)
        #expect(missing.limits == [.modelUnavailable("opus")])
        #expect(missing.limits[0].text(agent: "Codex", mode: "Fast") == "Codex doesn't offer opus, so Fast keeps the task's model.")
    }

    private func custom(_ settings: ModeSettings) -> Mode {
        Mode(id: .custom("fast"), name: "Fast", symbol: "hare", summary: "", instructions: "Go.", settings: settings, source: .custom)
    }
}
