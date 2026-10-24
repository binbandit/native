import ACP
import NativePolicy
import SwiftUI

struct ComposeAgentPicker: View {
    let model: AppModel

    private var policy: NativePolicy { PolicyCenter.shared.policy }
    private var isManaged: Bool { policy.isManaged(.agentsAllowed) || policy.isManaged(.forbiddenPermissionModes) }

    var body: some View {
        ComposerSettingsPopover(
            settings: ComposerSettings(
                model.composeTask.options.filter { ["model", "thought_level", "mode"].contains($0.category ?? "") }),
            agentName: model.composeTask.editor?.agentName ?? "The agent",
            manager: isManaged ? policy.organizationName ?? "your organization" : nil,
            forbiddenModes: policy.forbiddenPermissionModes,
            leadingContent: AnyView(agentChoices), showsExtras: false,
            managementExplanation: policy.isManaged(.agentsAllowed)
                ? "Your organization chooses which agents and permissions you can use."
                : "Your organization chooses which permissions you can use.",
            showsLockedConsequences: false,
            source: { _ in .user }, onSet: { model.composeTask.choose($0, value: $1) },
            connections: { EmptyView() }, actions: { EmptyView() })
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
