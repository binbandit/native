import ACP
import NativePolicy
import SwiftUI

/// The To line's popover: the agent, then the composer's own model, effort and asking sections.
/// Agent rows are drawn like the model rows under them, check first and at the same height.
struct ComposeAgentPicker: View {
    let model: AppModel
    var maxHeight = DS.ComposeTask.popoverMaxHeight

    private var policy: NativePolicy { PolicyCenter.shared.policy }
    private var isManaged: Bool { policy.isManaged(.agentsAllowed) || policy.isManaged(.forbiddenPermissionModes) }

    var body: some View {
        // The composer's popover caps itself for the composer; the page caps it to the room below To.
        CappedHeightScrollView(maxHeight: maxHeight) { settings }
    }

    private var settings: some View {
        ComposerSettingsPopover(
            settings: ComposerSettings(
                model.composeTask.options.filter { ["model", "thought_level", "mode"].contains($0.category ?? "") }),
            agentName: model.composeTask.editor?.agentName ?? "The agent",
            manager: isManaged ? policy.organizationName ?? "your organization" : nil,
            forbiddenModes: policy.forbiddenPermissionModes,
            leadingContent: AnyView(agentSection), showsExtras: false,
            managementExplanation: policy.isManaged(.agentsAllowed)
                ? "Your organization chooses which agents and permissions you can use."
                : "Your organization chooses which permissions you can use.",
            showsLockedConsequences: false,
            source: { _ in .user }, onSet: { model.composeTask.choose($0, value: $1) },
            connections: { EmptyView() }, actions: { EmptyView() })
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Agent").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                VStack(spacing: 0) {
                    ForEach(model.quickEntryRuntimes, id: \.agent.id, content: agentRow)
                    if model.quickEntry.device == .thisMac { addAgentRow }
                }
                if model.quickEntryRuntimes.isEmpty {
                    Text("No agents are available on this device. Choose another device or add an agent.")
                        .font(.dsBody).foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.ComposerSettings.sectionInset)
            // The same space around the rule as between the sections after it.
            SeparatorLine().padding(.bottom, DS.Space.xs)
        }
    }

    private func agentRow(_ runtime: AgentRuntime) -> some View {
        let allowed = policy.agents.allows(runtime.agent.id.rawValue)
        let selected = model.quickEntry.agent == runtime.agent.id
        let status =
            !allowed
            ? "Not allowed"
            : runtime.needsSignIn ? "Needs sign-in" : runtime.status == .idle ? "Ready" : runtime.status.label
        return HStack(spacing: DS.Space.sm) {
            Button {
                model.chooseComposeAgent(runtime.agent.id)
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "checkmark").font(DS.ComposerSettings.rowFont)
                        .opacity(selected ? 1 : 0)
                        .frame(width: DS.ComposerSettings.selectionWidth)
                    Text(runtime.agent.displayName).font(DS.ComposerSettings.rowFont).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: DS.Space.sm)
                    HStack(spacing: DS.Space.xs) {
                        if !allowed { Image(systemName: "lock") }
                        Text(status)
                    }
                    .font(.dsCaption)
                    .foregroundStyle(allowed && runtime.needsSignIn ? .dsAttention : .dsTextTertiary)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(allowed && runtime.isAvailable ? .dsTextPrimary : .dsTextTertiary)
            .disabled(!allowed || !runtime.isAvailable)
            .accessibilityLabel(runtime.agent.displayName)
            .accessibilityValue(status)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if allowed, runtime.status.canRetry {
                Button("Retry") { Task { await model.restart(runtime.agent.id) } }
                    .buttonStyle(.ds(.secondary, size: .small))
                    .accessibilityLabel("Retry \(runtime.agent.displayName)")
            }
        }
        .padding(.horizontal, DS.Space.xs)
        .frame(height: DS.ComposerSettings.rowHeight)
        .background(selected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control))
        .dsHitTarget(DS.ComposerSettings.controlHeight)
    }

    private var addAgentRow: some View {
        Button {
            model.isAddingAgent = true
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "plus").font(DS.ComposerSettings.rowFont).foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.ComposerSettings.selectionWidth)
                Text("Add Agent…").font(DS.ComposerSettings.rowFont)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.xs)
            .frame(height: DS.ComposerSettings.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.dsTextPrimary)
    }
}

#if DEBUG
#Preview("Compose - Agent and settings") {
    DSPreviewPair {
        ComposeAgentPicker(model: ComposeTaskPreviewFixtures.model("agents"))
            .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.card))
    }
}
#endif
