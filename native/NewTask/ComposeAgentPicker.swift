import ACP
import NativePolicy
import SwiftUI

struct ComposeAgentPicker: View {
    let model: AppModel
    @State private var resumedPermission: String?

    private var policy: NativePolicy { PolicyCenter.shared.policy }
    private var isManaged: Bool { policy.isManaged(.agentsAllowed) || policy.isManaged(.forbiddenPermissionModes) }

    private var settings: ComposerSettings {
        ComposerSettings(
            model.composeTask.options.filter { ["model", "thought_level", "mode"].contains($0.category ?? "") })
    }

    var body: some View {
        ComposerSettingsPopover(
            settings: settings,
            agentName: model.composeTask.editor?.agentName ?? "The agent",
            manager: isManaged ? policy.organizationName ?? "your organization" : nil,
            managementExplanation: policy.isManaged(.agentsAllowed)
                ? "Your organization chooses which agents and permissions you can use."
                : "Your organization chooses which permissions you can use.",
            forbiddenModes: policy.forbiddenPermissionModes,
            showsLockedConsequences: false, leadingContent: AnyView(agentChoices),
            rows: modeRows, resumedAutonomy: resumedPermission,
            onClose: { model.quickEntry.picker = nil }, onSet: choose)
    }

    /// Before a task exists, Plan still needs a Mode row of its own.
    private var modeRows: [ComposerSettingsTaskRow] {
        guard let plan = settings.plan else { return [] }
        let build =
            resumedPermission ?? model.composeTask.defaults["mode"].flatMap { $0 == "plan" ? nil : $0 }
            ?? plan.setting.choices.first { $0.value != plan.plan.value }?.value
        let choices: [ComposerSettingsTaskRow.Choice] = [
            .init(id: "build", name: "Build", isCurrent: !plan.isOn),
            .init(id: "plan", name: "Plan", isCurrent: plan.isOn),
        ].filter { $0.id != "plan" || !policy.forbiddenPermissionModes.contains(plan.plan.value) }
        return [
            ComposerSettingsTaskRow(
                id: "compose-mode", title: "Mode", value: plan.isOn ? "Plan" : "Build",
                kind: .menu(choices, commands: [])
            ) { value in
                if value == "plan" {
                    choose(plan.setting, plan.plan.value)
                } else if let build {
                    choose(plan.setting, build)
                }
            }
        ]
    }

    private func choose(_ setting: SelectSetting, _ value: String) {
        if let plan = settings.plan, setting.option.id == plan.setting.option.id,
            value == plan.plan.value, !plan.isOn
        {
            resumedPermission = setting.value
        }
        model.composeTask.choose(setting, value: value)
    }

    private var agentChoices: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            heading("Agent")
            ForEach(model.quickEntryRuntimes, id: \.agent.id) { runtime in
                let allowed = PolicyCenter.shared.policy.agents.allows(runtime.agent.id.rawValue)
                ComposerPickerRow(
                    title: runtime.agent.displayName,
                    detail: nil,
                    status: allowed
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
            SeparatorLine()
        }.padding(DS.Space.sm)
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
