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
                            if compose.second == nil && !compose.isHeld {
                                Image(systemName: "chevron.down").font(.dsMicro).foregroundStyle(.dsTextTertiary)
                            }
                        }
                    }
                    .buttonStyle(ComposeAddressButtonStyle())
                    .disabled(compose.isHeld)
                    .dsHitTarget(DS.ComposeTask.rowHeight)
                    .frame(minHeight: DS.ComposeTask.rowHeight)
                    .accessibilityLabel("Choose task agent and model")
                    .composeAddressPopover(isPresented: entry.picker == .agent, dismiss: { entry.picker = nil }) {
                        ComposeAgentPicker(model: model, maxHeight: $0)
                    }
                    if let second = compose.second {
                        ComposeSecondRecipient(model: model, compose: compose, second: second)
                    } else if !compose.isHeld, model.composeOffersSecondAgent, !model.composeSecondAgentChoices.isEmpty
                    {
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
            .zIndex(entry.picker == .agent ? 1 : 0)
            line("On") {
                // The offline note reads as a second line of the device's name, so no gap.
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        entry.toggle(.device)
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: deviceLook.symbol.systemImage)
                                .foregroundStyle(isOffline ? .dsTextTertiary : .dsTextSecondary)
                            Text(deviceName).foregroundStyle(.dsTextPrimary)
                            if model.composeDeviceOption?.availability == .connecting {
                                Text("Connecting…").foregroundStyle(.dsTextTertiary)
                            } else if model.composeDeviceOption?.availability == .online,
                                model.composeDeviceOption?.canStart == false
                            {
                                Text("Needs a checkout").foregroundStyle(.dsAttention)
                            } else if model.composeDeviceOption?.canStart == false {
                                HStack(spacing: DS.Space.sm) {
                                    StatusDot(color: .dsAttention)
                                    Text(model.composeDeviceOfflineSince.map { "Offline since \($0)" } ?? "Offline")
                                }
                                .foregroundStyle(.dsAttention)
                                .padding(.leading, DS.Space.xs)
                            }
                        }
                        .composeFocus(entry.picker == .device)
                    }
                    .buttonStyle(ComposeAddressButtonStyle()).dsHitTarget(DS.ComposeTask.rowHeight).disabled(
                        compose.isHeld
                    )
                    .frame(minHeight: DS.ComposeTask.rowHeight)
                    .accessibilityLabel("Choose task device")
                    .composeAddressPopover(isPresented: entry.picker == .device, dismiss: { entry.picker = nil }) {
                        QuickEntryPicker(model: model, entry: entry)
                            .frame(width: DS.ComposeTask.popoverWidth).frame(maxHeight: $0)
                    }
                    if entry.device.isRemote, model.composeDeviceOption?.canStart == false || compose.isHeld {
                        offline
                    }
                }
            }
            .zIndex(entry.picker == .device ? 1 : 0)
            if entry.project != nil {
                line("From") {
                    if let second = compose.second {
                        // Each agent gets a worktree of its own; nothing to choose.
                        VStack(alignment: .leading, spacing: 0) {
                            ownWorktree(for: model.quickEntryRuntime?.agent.displayName ?? "The first agent")
                            ownWorktree(for: model.plugins.agent(second.agent)?.displayName ?? second.agent.rawValue)
                        }
                        // The first line centers on the label's row, as a single line would.
                        .padding(.vertical, (DS.ComposeTask.rowHeight - DS.ComposeTask.tokenHeight) / 2)
                    } else if model.offersProjectFolderTasks {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            HStack(spacing: DS.Space.sm) {
                                TaskFolderChoice(
                                    isProjectFolder: compose.workspace == .project,
                                    sharedFolderNote: nil,
                                    choose: model.chooseComposeWorkspace,
                                    more: compose.beginWorkspaceSelection
                                )
                                .disabled(compose.isHeld || compose.isReadingWorkspaces)
                                Text(workspaceBranch).font(.dsMono).foregroundStyle(.dsTextTertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            if compose.workspace == .project, let project = entry.project,
                                let note = model.projectFolderNote(in: project, on: entry.device)
                            {
                                Text(note).font(.dsCallout).foregroundStyle(.dsTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Button {
                            compose.beginWorkspaceSelection()
                        } label: {
                            HStack(spacing: DS.Space.sm) {
                                Text(workspaceBranch).font(.dsMono).foregroundStyle(.dsTextSecondary)
                                if compose.workspace == .newWorktree {
                                    Text("→").font(.dsMono).foregroundStyle(.dsTextTertiary)
                                    Text("a new branch").foregroundStyle(.dsTextSecondary)
                                }
                                Text(workspaceDetail).foregroundStyle(.dsTextTertiary)
                            }
                        }
                        .buttonStyle(ComposeAddressButtonStyle()).dsHitTarget(DS.ComposeTask.rowHeight)
                        .disabled(entry.project == nil || compose.isHeld)
                        .accessibilityLabel("Choose task workspace")
                    }
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
        .background(compose.second == nil ? .clear : tokenFill, in: .rect(cornerRadius: DS.Radius.control))
        .composeFocus(compose.second == nil && entry.picker == .agent)
    }

    /// A token is already filled, so while its popover is open the fill itself is the highlight.
    private var tokenFill: Color { entry.picker == .agent ? .dsSelected : .dsFill }

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
        .menuStyle(.button).buttonStyle(ComposeAddressButtonStyle()).menuIndicator(.hidden).fixedSize()
        .disabled(compose.isHeld)
        .dsHitTarget(DS.ComposeTask.rowHeight)
        .help("Send the same task to a second agent, in its own worktree")
        .accessibilityLabel("Add a second agent")
    }

    private func ownWorktree(for agent: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(workspaceBranch).font(.dsMono).foregroundStyle(.dsTextSecondary)
            Text("→").font(.dsMono).foregroundStyle(.dsTextTertiary)
            Text("a new branch").foregroundStyle(.dsTextSecondary)
            Text("for \(agent)").foregroundStyle(.dsTextSecondary)
        }
        .frame(height: DS.ComposeTask.tokenHeight)
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
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(
                compose.isHeld
                    ? "Held for \(deviceName). Starts when it reconnects. You can cancel the hold and keep writing."
                    : model.composeDeviceNote
                        ?? "Native can hold this task until the device is back."
            )
            .font(.dsBody).lineSpacing(DS.ComposeTask.noteLineSpacing).foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: DS.ComposeTask.noteWidth, alignment: .leading)
            HStack(spacing: DS.Space.sm) {
                if compose.isHeld {
                    Button("Cancel Hold") { compose.cancelHold() }.buttonStyle(.ds(.secondary, size: .medium))
                } else {
                    // Return in the draft holds it too, as it starts a task anywhere else.
                    Button {
                        model.holdComposeTask()
                    } label: {
                        ComposeKeyLabel(title: "Hold for \(deviceName)", systemImage: "clock")
                    }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(!compose.hasContent || compose.pendingAttachments || !canHold)
                    .help("Hold the task for \(deviceName) (Return)")
                    Button("Run on This Mac") { model.chooseQuickEntryDevice(.thisMac) }
                        .buttonStyle(.ds(.secondary, size: .medium))
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

    @Environment(\.hostLookStore) private var injectedLooks
    private var deviceLook: HostLook {
        (injectedLooks ?? .shared).look(for: entry.device, named: deviceName)
    }
    private var deviceName: String { model.composeDeviceOption?.name ?? model.deviceName(entry.device) }
    private var isOffline: Bool {
        if case .offline = model.composeDeviceOption?.availability { return true }
        return false
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
        switch compose.workspace {
        case .newWorktree, .newWorktreeFrom:
            entry.device.isRemote ? "its own worktree on \(deviceName)" : "its own worktree"
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
