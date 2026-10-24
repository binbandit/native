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
                Button {
                    entry.toggle(.agent)
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Text(model.quickEntryRuntime?.agent.displayName ?? compose.editor?.agentName ?? "Choose agent")
                            .foregroundStyle(.dsTextPrimary)
                        if let name = ComposerSettings(compose.options).model?.currentName ?? model.quickEntryModelName
                        {
                            Text(name).foregroundStyle(.dsTextSecondary)
                        }
                        Image(systemName: "chevron.down").font(.dsMicro).foregroundStyle(.dsTextTertiary)
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
                            if model.composeDeviceOption?.canStart == false {
                                if let offlineSince {
                                    Text("Offline since \(offlineSince, format: .dateTime.hour().minute())")
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
                } else {
                    Button {
                        compose.showsWorkspaces = true
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
    private var offlineSince: Date? {
        #if DEBUG
        if let date = compose.previewOfflineSince { return date }
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
