#if DEBUG
import SwiftUI

// Task Settings' states (popover.html, a to h), each in light and dark.

private typealias Fixtures = ComposerSettingsPreviewFixtures

private struct PopoverPreview: View {
    let popover: ComposerSettingsPopover

    var body: some View {
        DSPreviewPair {
            popover.dsPopoverBackground()
        }
    }
}

#Preview("Task settings - a. Codex at rest") {
    PopoverPreview(
        popover: ComposerSettingsPopover(
            settings: Fixtures.codex(), agentName: "Codex", workspace: "fix/queued-row",
            rows: Fixtures.rows(agent: false), onSet: { _, _ in }))
}

#Preview("Task settings - b. Claude Code") {
    PopoverPreview(
        popover: ComposerSettingsPopover(
            settings: Fixtures.claude(), agentName: "Claude Code", workspace: "fix/queued-row",
            rows: Fixtures.rows(), onSet: { _, _ in }))
}

#Preview("Task settings - c. Many models, filtered") {
    DSPreviewPair {
        HStack(alignment: .top) {
            ForEach(["", "sonnet", "opsu"], id: \.self) { query in
                ComposerSettingsPopover(
                    settings: Fixtures.claude(models: Fixtures.gatewayModels), agentName: "Claude Code",
                    workspace: "fix/queued-row", rows: Fixtures.rows(), onSet: { _, _ in }, query: query
                )
                .dsPopoverBackground()
            }
        }
    }
}

#Preview("Task settings - d. Plan on") {
    PopoverPreview(
        popover: ComposerSettingsPopover(
            settings: Fixtures.claude(mode: "plan"), agentName: "Claude Code", workspace: "fix/queued-row",
            rows: Fixtures.rows(mode: "Plan"), resumedAutonomy: "acceptEdits", onSet: { _, _ in }))
}

#Preview("Task settings - e. Managed") {
    PopoverPreview(
        popover: ComposerSettingsPopover(
            settings: Fixtures.codex(mode: "read-only"), agentName: "Codex", workspace: "fix/queued-row",
            manager: "Northwind Federal IT", permissionsManaged: true,
            forbiddenModes: ["workspace-write", "agent", "agent-full-access"],
            rows: Fixtures.rows(mcp: "3", agent: false),
            onSet: { _, _ in }))
}

#Preview("Task settings - f. Failed server, stopped agent") {
    DSPreviewPair {
        HStack(alignment: .top) {
            ComposerSettingsPopover(
                settings: Fixtures.claude(), agentName: "Claude Code", workspace: "fix/queued-row",
                rows: Fixtures.rows(failed: "1 failed", agent: false), onSet: { _, _ in }
            )
            .dsPopoverBackground()
            ComposerSettingsPopover(
                settings: Fixtures.claude(), agentName: "Claude Code", workspace: "fix/queued-row",
                rows: Fixtures.rows(), isStopped: true, onRestart: {}, onSet: { _, _ in }
            )
            .dsPopoverBackground()
        }
    }
}

#Preview("Task settings - g. Keyboard") {
    PopoverPreview(
        popover: ComposerSettingsPopover(
            settings: Fixtures.codex(), agentName: "Codex", workspace: "fix/queued-row",
            rows: Fixtures.rows(agent: false), onSet: { _, _ in }, highlighted: .autonomy("agent-full-access")))
}

#Preview("Task settings - Applying, failed and no model") {
    DSPreviewPair {
        HStack(alignment: .top) {
            ComposerSettingsPopover(
                settings: Fixtures.claude(), agentName: "Claude Code", rows: Fixtures.rows(),
                pending: .init(optionID: "model", value: "sonnet"), onSet: { _, _ in }
            )
            .dsPopoverBackground()
            ComposerSettingsPopover(
                settings: Fixtures.claude(), agentName: "Claude Code", rows: Fixtures.rows(),
                failure: .init(
                    optionID: "model", message: "Couldn't switch to Sonnet 5.5. Haiku 5.5 is still on.", retry: {}),
                onSet: { _, _ in }
            )
            .dsPopoverBackground()
            ComposerSettingsPopover(
                settings: ComposerSettings([]), agentName: "Pi", rows: Fixtures.rows(agent: false), onSet: { _, _ in }
            )
            .dsPopoverBackground()
        }
    }
}

#Preview("Task settings - Mode's choices") {
    PopoverPreview(
        popover: ComposerSettingsPopover(
            settings: Fixtures.claude(), agentName: "Claude Code", rows: Fixtures.rows(), onSet: { _, _ in },
            page: .choices("mode")))
}
#Preview("Task settings - Crowded eight models, managed and stopped") {
    DSPreviewPair {
        ComposerSettingsPopover(
            settings: Fixtures.claude(
                models: Fixtures.claudeModels + ","
                    + #"{"value":"extra-one","name":"Extra model one"},{"value":"extra-two","name":"Extra model two"}"#),
            agentName: "Claude Code", manager: "Northwind Federal IT", permissionsManaged: true,
            rows: Fixtures.rows()
                + (0..<5).map {
                    ComposerSettingsTaskRow(id: "extra-\($0)", title: "Project setting", value: "Default", kind: .page)
                    { _ in }
                }, isStopped: true, onRestart: {}, onSet: { _, _ in }
        )
        .dsPopoverBackground()
    }
}

#endif
