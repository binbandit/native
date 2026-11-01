#if DEBUG
import ACP
import SwiftUI

/// Inert adapter choices for the two-agent and four-agent discovery states.
enum ComposerAgentSwitchFixtures {
    static func agents(count: Int) -> [ComposerAgentModel] {
        let agents = [("claude-code", "Claude Code"), ("codex", "Codex"), ("copilot", "Copilot"), ("cursor", "Cursor")]
        return agents.prefix(count).map { id, name in
            ComposerAgentModel(
                agent: .init(rawValue: id), agentName: name, choice: .init(value: "", name: "Default"),
                kind: .model(nil))
        }
    }

    static func models(count: Int) -> [ComposerAgentModel] {
        agents(count: count).flatMap { agent in
            let settings =
                agent.agent.rawValue == "claude-code"
                ? ComposerSettingsPreviewFixtures.claude() : ComposerSettingsPreviewFixtures.codex()
            return settings.model?.choices.map {
                ComposerAgentModel(agent: agent.agent, agentName: agent.agentName, choice: $0, kind: .model($0.value))
            } ?? [agent]
        }
    }
}

#Preview("Switch Agent - Fine print, two and four agents") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            ForEach([2, 4], id: \.self) { count in
                VStack {
                    ComposerSettingsPopover(
                        settings: ComposerSettingsPreviewFixtures.claude(), agentName: "Claude Code",
                        rows: ComposerSettingsPreviewFixtures.rows(),
                        agentModels: ComposerAgentSwitchFixtures.models(count: count),
                        currentAgentID: .init(rawValue: "claude-code"), onChooseAgent: { _ in }, onSet: { _, _ in }
                    )
                    .dsPopoverBackground()
                    ComposerSettingsDoorLabel(mode: nil, model: "Haiku 5.5", agent: "Claude Code", isOpen: true)
                }
            }
        }
    }
}

#Preview("Switch Agent - Legacy, two and four agents") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            ForEach([2, 4], id: \.self) { count in
                let settings = ComposerSettingsPreviewFixtures.claude()
                let picker = ComposerAgentPicker(
                    models: ComposerAgentSwitchFixtures.models(count: count), current: .init(rawValue: "claude-code"),
                    onChoose: { _ in })
                VStack {
                    ModelPicker(
                        agentPicker: picker, model: settings.model, effort: settings.effort, switches: [],
                        onSet: { _, _ in }, dismiss: {}
                    )
                    .dsPopoverBackground()
                    ModelPill(
                        agentName: "Claude Code", agentPicker: picker, model: settings.model, effort: settings.effort,
                        switches: [], isPickerOpen: .constant(false), onSet: { _, _ in }, onCycleEffort: {})
                }
            }
        }
    }
}
#endif
