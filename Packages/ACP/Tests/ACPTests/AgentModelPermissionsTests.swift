import Foundation
import Testing

@testable import ACP

@Suite struct AgentModelPermissionsTests {
    @Test func equalLevelsKeepTheClosestChoice() {
        #expect(AgentModelPermissions.replacement(for: "auto", offered: ["default", "auto"]) == "auto")
        #expect(
            AgentModelPermissions.selection(for: "auto", offered: ["default", "agent"])
                == .init(value: "agent", reason: .equivalent))
        #expect(
            AgentModelPermissions.replacement(for: "acceptEdits", offered: ["workspace-write", "read-only"])
                == "read-only")
    }

    @Test func stricterOnlyUsesTheClosestLevel() {
        #expect(
            AgentModelPermissions.selection(for: "bypassPermissions", offered: ["default", "acceptEdits"])
                == .init(value: "acceptEdits", reason: .stricter))
        #expect(AgentModelPermissions.replacement(for: "bypassPermissions", offered: ["default", "agent"]) == "agent")
    }

    @Test func riskReviewDoesNotImplyTrustedEditsAreSafe() {
        #expect(AgentModelPermissions.replacement(for: "auto", offered: ["acceptEdits", "default"]) == "default")
        #expect(
            AgentModelPermissions.replacement(for: "agent", offered: ["workspace-write", "read-only"]) == "read-only")
    }

    @Test func planCannotBecomeOrdinaryApprovalsSilently() {
        #expect(
            AgentModelPermissions.selection(for: "plan", offered: ["default"])
                == .init(value: "default", reason: .safestAvailable))
        #expect(
            AgentModelPermissions.selection(for: "plan", offered: ["default", "plan"])
                == .init(value: "plan", reason: .equivalent))
    }

    @Test func readOnlyDoesNotBecomeOrdinaryApprovalsSilently() {
        #expect(AgentModelPermissions.selection(for: "read-only", offered: ["default"])?.reason == .safestAvailable)
        #expect(AgentModelPermissions.replacement(for: "read-only", offered: ["default", "plan"]) == "plan")
        #expect(AgentModelPermissions.replacement(for: "plan", offered: ["default", "read-only"]) == "read-only")
    }

    @Test func noSafeMatchUsesSafestOfferedAndReportsIt() {
        #expect(
            AgentModelPermissions.selection(for: "default", offered: ["agent-full-access", "workspace-write"])
                == .init(value: "workspace-write", reason: .safestAvailable))
    }

    @Test func policyLockedModesNeverParticipate() {
        #expect(
            AgentModelPermissions.replacement(for: "auto", offered: ["default", "auto"], forbidden: ["auto"])
                == "default")
        #expect(
            AgentModelPermissions.replacement(
                for: "default", offered: ["auto", "default"], forbidden: ["auto", "default"]) == nil)
        #expect(
            AgentModelPermissions.selection(
                for: "default", offered: ["auto", "agent-full-access"], forbidden: ["auto"])
                == .init(value: "agent-full-access", reason: .safestAvailable))
    }

    @Test func unknownModesUseAnExplicitFallback() {
        #expect(AgentModelPermissions.isConservative("default"))
        #expect(!AgentModelPermissions.isConservative("interactive"))
        #expect(!AgentModelPermissions.isConservative("bypassPermissions"))
        #expect(
            AgentModelPermissions.selection(for: "auto", offered: ["interactive", "autopilot"])
                == .init(value: "interactive", reason: .unknown))
        #expect(
            AgentModelPermissions.selection(for: "custom", offered: ["bypassPermissions", "default", "custom"])
                == .init(value: "default", reason: .unknown))
        #expect(AgentModelPermissions.selection(for: "dontAsk", offered: ["default"])?.reason == .unknown)
        #expect(AgentModelPermissions.replacement(for: "auto", offered: ["bypassPermissions", "dontAsk"]) == "dontAsk")
        #expect(AgentModelPermissions.selection(for: nil, offered: ["auto", "default"])?.value == "default")
        #expect(
            AgentModelPermissions.selection(for: "default", offered: ["custom", "bypassPermissions"])?.reason
                == .unknown)
        #expect(AgentModelPermissions.selection(for: "auto", offered: []) == nil)
    }

    @Test func capturedClaudeCodeOptions() throws {
        // claude-agent-acp 0.93.0 session/new, captured 2026-10-28; only permission config retained.
        let options = try JSONDecoder().decode([ConfigOption].self, from: Data(claudePermissionOptions.utf8))
        let mode = try #require(options.first { $0.category == "mode" })
        guard case .select(_, let choices) = mode.kind else { Issue.record("No select modes"); return }
        let offered = choices.map(\.value).filter { $0 != "plan" }
        #expect(AgentModelPermissions.replacement(for: "agent", offered: offered) == "auto")
        #expect(AgentModelPermissions.replacement(for: "agent-full-access", offered: offered) == "bypassPermissions")
        #expect(AgentModelPermissions.replacement(for: "auto", offered: offered, forbidden: ["auto"]) == "default")
    }

    private let claudePermissionOptions = #"""
        [
          {
            "id": "mode",
            "name": "Mode",
            "description": "Session permission mode",
            "category": "mode",
            "type": "select",
            "currentValue": "auto",
            "options": [
              {
                "value": "default",
                "name": "Manual",
                "description": "Always ask before making changes"
              },
              {
                "value": "acceptEdits",
                "name": "Accept edits",
                "description": "Automatically accept all file edits"
              },
              {
                "value": "plan",
                "name": "Plan",
                "description": "Create a plan before making changes"
              },
              {
                "value": "auto",
                "name": "Auto",
                "description": "Claude handles permission decisions"
              },
              {
                "value": "bypassPermissions",
                "name": "Bypass permissions",
                "description": "Accepts all permissions"
              }
            ]
          }
        ]
        """#
}
