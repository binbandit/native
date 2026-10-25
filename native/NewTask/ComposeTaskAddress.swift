import ACP
import SwiftUI

struct ComposeTaskAddress: View {
    let model: AppModel
    let branch: String?
    @Bindable var compose: ComposeTaskModel
    @Bindable var entry: QuickEntryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line("To") {
                HStack(spacing: DS.Space.sm) {
                    Button {
                        entry.toggle(.agent)
                    } label: {
                        recipient(
                            model.quickEntryRuntime?.agent.displayName ?? compose.editor?.agentName ?? "Choose agent",
                            model: ComposerSettings(compose.options).model?.currentName ?? model.quickEntryModelName
                        ) {
                            // Two agents read as two recipients, without pickers' chevrons.
                            if compose.second == nil {
                                Image(systemName: "chevron.down").font(.dsMicro).foregroundStyle(.dsTextTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(compose.isHeld)
                    .dsHitTarget(DS.ComposeTask.rowHeight)
                    .frame(minHeight: DS.ComposeTask.rowHeight)
                    .accessibilityLabel("Choose task agent and model")
                    .dsPopover(isPresented: picker(.agent), attachmentAnchor: .point(.bottomLeading), arrowEdge: .top) {
                        ComposeAgentPicker(model: model)
                    }
                    if let second = compose.second {
                        ComposeSecondRecipient(model: model, compose: compose, second: second)
                    } else if model.composeOffersSecondAgent, !model.composeSecondAgentChoices.isEmpty {
                        addRecipient
                    }
                    if compose.second != nil {
                        Spacer(minLength: DS.Space.lg)
                        Text("Side by side, each in its own worktree")
                            .font(.dsBody).foregroundStyle(.dsTextTertiary).lineLimit(1)
                    }
                }
                ForEach(consequences, id: \.self) { consequence in
                    Text(consequence).font(.dsBody).foregroundStyle(.dsTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            line("On") {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Button {
                        entry.toggle(.device)
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: entry.device == .thisMac ? "laptopcomputer" : "desktopcomputer")
                                .foregroundStyle(.dsTextSecondary)
                            Text(deviceName)
                            if model.composeDeviceOption?.availability == .connecting {
                                Text("Connecting…").foregroundStyle(.dsTextTertiary)
                            } else if model.composeDeviceOption?.availability == .online,
                                model.composeDeviceOption?.canStart == false
                            {
                                Text("Needs a checkout").foregroundStyle(.dsAttention)
                            } else if model.composeDeviceOption?.canStart == false {
                                if let lastConnected {
                                    Text("Offline · last connected \(lastConnected, format: .dateTime.hour().minute())")
                                        .foregroundStyle(.dsAttention)
                                } else {
                                    Text("Offline").foregroundStyle(.dsAttention)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain).dsHitTarget(DS.ComposeTask.rowHeight).disabled(compose.isHeld)
                    .frame(minHeight: DS.ComposeTask.rowHeight)
                    .accessibilityLabel("Choose task device")
                    .dsPopover(isPresented: picker(.device), attachmentAnchor: .point(.bottomLeading), arrowEdge: .top)
                    {
                        QuickEntryPicker(model: model, entry: entry).frame(width: DS.ComposeTask.popoverWidth)
                    }
                    if entry.device.isRemote, model.composeDeviceOption?.canStart == false || compose.isHeld {
                        offline
                    }
                }
            }
            line("From") {
                if entry.project == nil {
                    Text("A branch of its own, made from the folder's current branch")
                        .foregroundStyle(.dsTextTertiary)
                } else if let second = compose.second {
                    // Each agent gets a worktree of its own; nothing to choose.
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ownWorktree(for: model.quickEntryRuntime?.agent.displayName ?? "The first agent")
                        ownWorktree(for: model.plugins.agent(second.agent)?.displayName ?? second.agent.rawValue)
                    }
                    .frame(minHeight: DS.ComposeTask.rowHeight)
                } else {
                    Button {
                        compose.beginWorkspaceSelection()
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Text(workspaceBranch).font(.dsMono).foregroundStyle(.dsTextSecondary)
                            if compose.workspace == .newWorktree {
                                Text("→").font(.dsMono).foregroundStyle(.dsTextTertiary)
                                Text("new branch").font(.dsMono)
                            }
                            Text(workspaceDetail).foregroundStyle(.dsTextTertiary)
                        }
                    }
                    .buttonStyle(.plain).dsHitTarget(DS.ComposeTask.rowHeight)
                    .disabled(entry.project == nil || compose.isHeld)
                    .accessibilityLabel("Choose task workspace")
                }
            }
        }
        .font(.dsCallout)
    }

    /// An agent and its model on the To line; with two agents, each sits on a token.
    private func recipient<Trailing: View>(
        _ agent: String, model: String?, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(agent).foregroundStyle(.dsTextPrimary)
            if let model { Text(model).foregroundStyle(.dsTextSecondary) }
            trailing()
        }
        .padding(.horizontal, compose.second == nil ? 0 : DS.ComposeTask.tokenPadding)
        .frame(height: DS.ComposeTask.tokenHeight)
        .background(compose.second == nil ? .clear : .dsFill, in: .rect(cornerRadius: DS.Radius.control))
    }

    private var addRecipient: some View {
        Menu {
            Section("Also send to") {
                ForEach(model.composeSecondAgentChoices, id: \.agent.id) { runtime in
                    Button(runtime.agent.displayName) { model.addComposeAgent(runtime.agent.id) }
                }
            }
        } label: {
            Image(systemName: "plus").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                .frame(width: DS.ComposeTask.tokenHeight, height: DS.ComposeTask.tokenHeight)
                .contentShape(.rect)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(compose.isHeld)
        .dsHitTarget(DS.ComposeTask.rowHeight)
        .help("Send the same task to a second agent, in its own worktree")
        .accessibilityLabel("Add a second agent")
    }

    private func ownWorktree(for agent: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(workspaceBranch).font(.dsMono).foregroundStyle(.dsTextSecondary)
            Text("→").font(.dsMono).foregroundStyle(.dsTextTertiary)
            Text("new branch").font(.dsMono)
            Text("\(agent)'s own worktree").foregroundStyle(.dsTextTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func line<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs, content: content)
            .frame(maxWidth: .infinity, minHeight: DS.ComposeTask.rowHeight, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Text(label).font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.ComposeTask.labelWidth, height: DS.ComposeTask.rowHeight, alignment: .trailing)
                    .offset(x: -(DS.ComposeTask.labelWidth + DS.ComposeTask.labelGap))
            }
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(
                compose.isHeld
                    ? "Held for \(deviceName). Starts when it reconnects. You can cancel the hold and keep writing."
                    : model.composeDeviceOption?.unavailableReason
                        ?? "Native can hold this task until the device is back."
            )
            .font(.dsBody).foregroundStyle(.dsTextTertiary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.sm) {
                if compose.isHeld {
                    Button("Cancel Hold") { compose.cancelHold() }.buttonStyle(.ds(.secondary))
                } else {
                    Button("Hold for \(deviceName)") { model.holdComposeTask() }
                        .buttonStyle(.ds(.primary))
                        .disabled(!compose.hasContent || compose.pendingAttachments || !canHold)
                    Button("Run on This Mac") { model.chooseQuickEntryDevice(.thisMac) }
                        .buttonStyle(.ds(.secondary))
                }
            }
        }
        .padding(.bottom, DS.Space.md)
    }

    private var canHold: Bool {
        guard let option = model.composeDeviceOption else { return false }
        if case .cannotClone = option.checkout { return false }
        return true
    }

    private var deviceName: String { model.composeDeviceOption?.name ?? model.deviceName(entry.device) }
    private var lastConnected: Date? {
        #if DEBUG
        if let date = compose.previewLastConnected { return date }
        #endif
        guard case .remote(let id) = entry.device else { return nil }
        return model.hosts.host(id)?.lastConnected
    }
    private var workspaceBranch: String {
        if entry.project == nil { return "Choose a folder first" }
        return switch compose.workspace {
        case .branch(let name): name
        case .worktree(let folder): folder.lastPathComponent
        default: branch ?? (entry.project == nil ? "Choose a folder first" : "Current branch")
        }
    }
    private var workspaceDetail: String {
        if entry.project == nil { return "" }
        return switch compose.workspace {
        case .newWorktree: entry.device.isRemote ? "its own worktree on \(deviceName)" : "its own worktree"
        case .project: "in the project folder"
        case .branch, .worktree: "in its workspace"
        case nil: compose.isReadingWorkspaces ? "Reading workspaces…" : "project default"
        }
    }
    private var consequences: [String] {
        let settings = ComposerSettings(compose.options)
        return [settings.effort, settings.autonomy].compactMap { setting in
            guard let setting, let category = setting.option.category, compose.choices[category] != nil,
                let choice = setting.current
            else { return nil }
            if category == "mode" { return AutonomySummary.summary(of: choice) ?? choice.name }
            return "\(choice.name) effort"
                + (choice.descriptionWithoutName.map { ": \($0)" } ?? ": differs from the project default")
        }
    }
    private func picker(_ picker: QuickEntryModel.Picker) -> Binding<Bool> {
        Binding(get: { entry.picker == picker }, set: { if !$0 { entry.picker = nil } })
    }
}

#if DEBUG
#Preview("Compose - Address and offline hold") {
    DSPreviewPair {
        let model = ComposeTaskPreviewFixtures.model("offline")
        ComposeTaskAddress(model: model, branch: "main", compose: model.composeTask, entry: model.quickEntry)
            .padding(.leading, DS.ComposeTask.labelWidth + DS.ComposeTask.labelGap)
            .padding(DS.Space.xxl).frame(width: DS.ComposeTask.width)
    }
}
#endif
