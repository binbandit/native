import Foundation
import Testing

@testable import ACP

@Suite struct TaskPermissionTests {
    @Test func claudeCodeMapsEveryModeExactly() {
        let mapping = ClaudeCodeSessionSettings.permissionMapping
        let offered = ["default", "acceptEdits", "auto", "bypassPermissions", "dontAsk", "plan"]
        let expected = ["default", "acceptEdits", "auto", "bypassPermissions"]
        for (mode, wire) in zip(TaskPermissionMode.allCases, expected) {
            #expect(mapping.selection(mode, offered: offered) == .init(value: wire, effective: mode, isExact: true))
        }
    }

    @Test func codexUsesUserReviewAutoReviewAndFullAccessControls() {
        let mapping = CodexConfigOverrides.permissionMapping
        let offered = ["read-only", "workspace-write", "agent", "agent-full-access"]
        #expect(mapping.selection(.askFirst, offered: offered)?.value == "workspace-write")
        #expect(
            mapping.selection(.acceptEdits, offered: offered)
                == .init(value: "workspace-write", effective: .askFirst, isExact: false))
        #expect(mapping.selection(.auto, offered: offered)?.value == "agent")
        #expect(mapping.selection(.fullAccess, offered: offered)?.value == "agent-full-access")
    }

    @Test func acpAgentsUseOnlyKnownSemanticsAndNeverEscalate() {
        let mapping = TaskPermissionMapping.standard
        #expect(mapping.selection(.acceptEdits, offered: ["default", "bypassPermissions"])?.value == "default")
        #expect(mapping.selection(.auto, offered: ["default", "acceptEdits"])?.value == "acceptEdits")
        #expect(mapping.selection(.askFirst, offered: ["auto", "bypassPermissions"]) == nil)
        #expect(mapping.selection(.fullAccess, offered: ["custom", "yolo", "agent"]) == nil)
    }

    @Test func switchingNeverWidensSharedPermissionMode() {
        #expect(AgentModelPermissions.selection(for: "ask-first", offered: ["full-access"]) == nil)
        #expect(
            AgentModelPermissions.selection(for: "auto", offered: ["ask-first", "accept-edits"])?.value
                == "accept-edits")
        #expect(AgentModelPermissions.selection(for: "full-access", offered: ["ask-first", "auto"])?.value == "auto")
    }

    @Test func unavailableClaudeAutoFallsBackToEdits() {
        let mapping = ClaudeCodeSessionSettings.permissionMapping
        #expect(
            mapping.selection(.auto, offered: ["default", "acceptEdits", "bypassPermissions"])
                == .init(value: "acceptEdits", effective: .acceptEdits, isExact: false))
    }

    @Test func policyChecksNativeAndProviderValuesWithoutChoosingLooserMode() {
        let mapping = ClaudeCodeSessionSettings.permissionMapping
        let offered = ["default", "acceptEdits", "auto", "bypassPermissions"]
        #expect(mapping.selection(.fullAccess, offered: offered, forbidden: ["full-access"]) == nil)
        #expect(mapping.selection(.fullAccess, offered: offered, forbidden: ["bypassPermissions"])?.value == "auto")
        #expect(mapping.selection(.askFirst, offered: offered, forbidden: ["default"]) == nil)
        #expect(mapping.selection(.auto, offered: offered, forbidden: ["auto", "acceptEdits", "default"]) == nil)
    }

    @Test func presentedPickerRetainsModeAcrossStricterEquivalentAndExplainsIt() throws {
        let option = try JSONDecoder().decode(
            ConfigOption.self,
            from: Data(
                #"""
                {"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"workspace-write",
                 "options":[{"value":"workspace-write","name":"Workspace access"},{"value":"agent","name":"Auto review"},
                            {"value":"agent-full-access","name":"Full access"}]}
                """#.utf8))
        let shown = CodexConfigOverrides.permissionMapping.presenting(option, remembered: "accept-edits")
        guard case .select(let current, let choices) = shown.kind else { Issue.record("Missing select"); return }
        #expect(current == "accept-edits")
        #expect(choices.map(\.name) == ["Ask first", "Accept edits", "Auto", "Full access"])
        #expect(choices[1].description?.contains("Uses Ask first with this agent.") == true)
        #expect(choices[0].description?.contains("safe equivalent") == false)
        #expect(choices[0].description?.contains("outside access asks") == true)
        #expect(shown.permissionMappings?["accept-edits"] == "workspace-write")
        #expect(AgentModelPermissions.replacement(for: "accept-edits", offered: choices.map(\.value)) == "accept-edits")
    }

    @Test func taskModeRestrictionsRemainSeparateFromPermissionChoices() throws {
        let option = try JSONDecoder().decode(
            ConfigOption.self,
            from: Data(
                #"{"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"read-only","options":[{"value":"read-only","name":"Read only"},{"value":"workspace-write","name":"Workspace"},{"value":"agent-full-access","name":"Full access"}]}"#
                    .utf8))
        let shown = CodexConfigOverrides.permissionMapping.presenting(option)
        guard case .select(let current, let choices) = shown.kind else { Issue.record("Missing select"); return }
        #expect(current == "read-only")
        #expect(choices.filter { TaskPermissionMode(rawValue: $0.value) != nil }.count == 4)
        #expect(choices.contains { $0.value == "read-only" })
        let retained = TaskPermissionMapping.standard.presenting(option, remembered: "ask-first")
        guard case .select(let canonical, _) = retained.kind else { Issue.record("Missing select"); return }
        #expect(canonical == "ask-first")
    }

    @Test func migratesAllLegacyLevels() {
        let cases: [String: TaskPermissionMode] = [
            "default": .askFirst, "read-only": .askFirst, "dontAsk": .askFirst, "plan": .askFirst,
            "acceptEdits": .acceptEdits, "workspace-write": .acceptEdits, "auto": .auto, "agent": .auto,
            "bypassPermissions": .fullAccess, "agent-full-access": .fullAccess,
        ]
        for (old, mode) in cases { #expect(TaskPermissionMode.migrating(old) == mode) }
        #expect(TaskPermissionMode.migrating("unfamiliar") == nil)
    }

    @Test func unknownSavedDefaultMigratesConservatively() throws {
        let suite = "TaskPermissionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-provider-mode", forKey: "agentDefaults.first.permissions")
        #expect(TaskPermissionDefaults.value(defaults: defaults) == .askFirst)
        defaults.set("unknown-native-mode", forKey: TaskPermissionDefaults.key)
        #expect(TaskPermissionDefaults.value(defaults: defaults) == .askFirst)
    }

    @Test func newDefaultsFullAccessAndProjectOverridesSurviveMigrationAndReset() throws {
        let suite = "TaskPermissionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TaskPermissionDefaults.value(defaults: defaults) == .fullAccess)
        defaults.set("auto", forKey: "agentDefaults.first.permissions")
        defaults.set("acceptEdits", forKey: "agentDefaults.second.permissions")
        defaults.set("default", forKey: "projectDefaults.sample.first.permissions")
        #expect(TaskPermissionDefaults.value(defaults: defaults) == .acceptEdits)
        #expect(TaskPermissionDefaults.value(project: "sample", defaults: defaults) == .askFirst)
        defaults.set("full-access", forKey: TaskPermissionDefaults.key)
        #expect(TaskPermissionDefaults.value(defaults: defaults) == .fullAccess)
        #expect(TaskPermissionDefaults.value(project: "sample", defaults: defaults) == .askFirst)
        defaults.removeObject(forKey: TaskPermissionDefaults.key(project: "sample"))
        #expect(TaskPermissionDefaults.value(project: "sample", defaults: defaults) == .fullAccess)
        #expect(defaults.string(forKey: "agentDefaults.first.permissions") == nil)
        #expect(defaults.string(forKey: "projectDefaults.sample.first.permissions") == nil)
    }
}
