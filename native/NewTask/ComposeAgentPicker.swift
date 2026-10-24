import ACP
import NativePolicy
import SwiftUI

struct ComposeAgentPicker: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                heading("Agent")
                ForEach(model.quickEntryRuntimes, id: \.agent.id) { runtime in
                    let allowed = PolicyCenter.shared.policy.agents.allows(runtime.agent.id.rawValue)
                    ComposerPickerRow(
                        title: runtime.agent.displayName,
                        detail: allowed
                            ? runtime.needsSignIn
                                ? "Needs sign-in" : runtime.status == .idle ? "Ready" : runtime.status.label
                            : "Not allowed",
                        trailing: !allowed
                            ? .locked : model.quickEntry.agent == runtime.agent.id ? .checked(dimmed: false) : .none,
                        isEnabled: allowed && runtime.isAvailable
                    ) { model.chooseComposeAgent(runtime.agent.id) }
                    if allowed, runtime.status.canRetry {
                        Button("Retry \(runtime.agent.displayName)") { Task { await model.restart(runtime.agent.id) } }
                            .buttonStyle(.ds(.secondary))
                    }
                }
                if model.quickEntryRuntimes.isEmpty {
                    Text("No agents are available on this device. Choose another device or add an agent.")
                        .font(.dsBody).foregroundStyle(.dsTextSecondary).padding(DS.Space.md)
                }
                if model.quickEntry.device == .thisMac {
                    Button("Add Agent…") { model.isAddingAgent = true }
                        .buttonStyle(.ds(.ghost))
                }
                let settings = ComposerSettings(model.composeTask.options)
                if let setting = settings.model { choices(setting, title: "Model") }
                if let setting = settings.effort { choices(setting, title: "Effort") }
                if let setting = settings.autonomy {
                    choices(setting, title: "When \(model.composeTask.editor?.agentName ?? "the agent") asks you")
                }
                if settings.model == nil {
                    SeparatorLine()
                    Text("Uses the project's defaults. More choices appear after this agent has reported its settings.")
                        .font(.dsBody).foregroundStyle(.dsTextTertiary).padding(DS.Space.md)
                }
                if !PolicyCenter.shared.policy.managedKeys.isEmpty {
                    SeparatorLine()
                    Label {
                        Text(
                            "Managed by \(PolicyCenter.shared.policy.organizationName ?? "your organization"). Your organization chooses which agents and permissions you can use."
                        )
                    } icon: {
                        Image(systemName: "lock")
                    }
                    .font(.dsCaption).foregroundStyle(.dsTextSecondary).padding(DS.Space.md)
                }
            }
            .padding(DS.Space.sm)
        }
        .frame(width: DS.ComposeTask.popoverWidth)
        .frame(maxHeight: DS.ComposeTask.popoverMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func choices(_ setting: SelectSetting, title: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SeparatorLine()
            heading(title)
            ForEach(
                setting.choices.filter { setting.option.category != "mode" || $0.value != ComposerSettings.planValue }
            ) { choice in
                let forbidden = PolicyPermissionModes.forbids(setting.option, value: choice.value)
                ComposerPickerRow(
                    title: choice.name,
                    detail: forbidden
                        ? "Not allowed"
                        : setting.option.category == "mode"
                            ? AutonomySummary.summary(of: choice)
                            : choice.descriptionWithoutName,
                    trailing: forbidden ? .locked : choice.value == setting.value ? .checked(dimmed: false) : .none,
                    isEnabled: !forbidden
                ) { model.composeTask.choose(setting, value: choice.value) }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.dsCaption).foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.md).padding(.top, DS.Space.sm)
    }
}

#if DEBUG
#Preview("Compose - Agent and settings") {
    DSPreviewPair { ComposeAgentPicker(model: ComposeTaskPreviewFixtures.model("agents")) }
}
#endif
