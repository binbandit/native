#if DEBUG
import ACP
import NativeHostProtocol

/// Earlier agents' work as a marker shows it, for previews: history items read back the way the
/// transcript reads them.
enum TaskHistoryPreviewFixtures {
    static let twoAgents = TaskHistoryContext(runs: [claude, codex], omitsEarlier: false, agent: agent)

    static let omitsEarlier = TaskHistoryContext(runs: [codex], omitsEarlier: true, agent: agent)

    private static let claude = TaskHistoryRun(
        participant: participant(1, "claude-code"),
        items: items(
            from: 1,
            [
                .user(.init(text: "Why does the settings test fail on CI?")),
                .tool(.init(id: "t1", title: "Read SettingsTests.swift", kind: "read", status: "completed")),
                .tool(
                    .init(
                        id: "t2", title: "swift test --filter SettingsTests", kind: "execute", status: "failed",
                        input: "swift test --filter SettingsTests")),
                .agent(
                    "It reads your real defaults. On CI those are empty, so the theme falls back to light and the "
                        + "snapshot differs."),
            ]))

    private static let codex = TaskHistoryRun(
        participant: participant(2, "codex"),
        items: items(
            from: 5,
            [
                .user(.init(text: "Give it a defaults suite of its own.")),
                .tool(.init(id: "t3", title: "Edit SettingsTests.swift", kind: "edit", status: "completed")),
                .agent("Done: the test now uses an isolated suite, and it passes on a clean machine."),
            ]))

    private static func agent(_ id: String) -> AgentDefinition? {
        let name = id == "codex" ? "Codex" : "Claude Code"
        return AgentDefinition(AgentManifest(id: id, name: name, command: id), pluginID: "preview")
    }

    private static func participant(_ ordinal: Int, _ agentID: String) -> TaskHistoryParticipant {
        TaskHistoryParticipant(ordinal: ordinal, agentID: agentID, agentSessionID: SessionID("preview-\(ordinal)"))
    }

    private static func items(from seq: Int, _ bodies: [TaskHistoryItem.Body]) -> [TaskHistoryItem] {
        bodies.enumerated().map { TaskHistoryItem(seq: seq + $0.offset, source: 1, body: $0.element) }
    }
}
#endif
