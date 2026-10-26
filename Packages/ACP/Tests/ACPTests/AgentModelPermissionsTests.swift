import Testing

@testable import ACP

@Suite struct AgentModelPermissionsTests {
    @Test func neverBroadensPermissions() {
        for source in ["default", "read-only", "acceptEdits", "workspace-write", "auto", "agent", "bypassPermissions"] {
            #expect(
                AgentModelPermissions.replacement(for: source, offered: ["workspace-write", "read-only", "agent"])
                    == "read-only")
            #expect(
                AgentModelPermissions.replacement(for: source, offered: ["bypassPermissions", "default"]) == "default")
            #expect(AgentModelPermissions.replacement(for: source, offered: ["workspace-write", "agent"]) == nil)
        }
    }

    @Test func unknownModesAndRefuseModesFailClosed() {
        for source in ["custom-policy", "dontAsk", "plan"] {
            #expect(AgentModelPermissions.replacement(for: source, offered: [source, "default", "read-only"]) == nil)
        }
    }

    @Test func managedModesNeverParticipate() {
        #expect(
            AgentModelPermissions.replacement(
                for: "default", offered: ["read-only", "default"], forbidden: ["read-only"]) == "default")
        #expect(
            AgentModelPermissions.replacement(for: "default", offered: ["read-only"], forbidden: ["read-only"]) == nil)
    }
}
