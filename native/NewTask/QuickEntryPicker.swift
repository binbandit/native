import SwiftUI

struct QuickEntryPicker: View {
    let model: AppModel
    @Bindable var entry: QuickEntryModel
    @Environment(\.openAddHost) private var openAddHost

    var body: some View {
        ScrollView {
            switch entry.picker {
            case .device:
                HostDevicePicker(
                    options: deviceOptions,
                    projectName: entry.project.flatMap(model.projects.project)?.name ?? "the project",
                    selection: Binding(get: { entry.device }, set: model.chooseQuickEntryDevice),
                    onAddHost: openAddHost.map { action in { action() } }, width: nil,
                    allowsOfflineHold: model.composeTask.isPresented,
                    offlineSince: { model.composeOfflineSince(for: $0) }
                ) { entry.picker = nil }
            case .agent:
                agents
            case .project:
                projects
            case nil:
                EmptyView()
            }
        }
        .frame(maxHeight: DS.QuickEntry.pickerMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var deviceOptions: [SessionDeviceOption] {
        #if DEBUG
        if let options = entry.previewDeviceOptions { return options }
        #endif
        return entry.project.map(model.deviceOptions(for:)) ?? [model.noProjectDeviceOption]
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            heading("Agent")
            ForEach(model.quickEntryRuntimes, id: \.agent.id) { runtime in
                HStack(spacing: DS.Space.md) {
                    Button {
                        entry.agent = runtime.agent.id
                        entry.failure = nil
                        entry.picker = nil
                    } label: {
                        HStack(spacing: DS.Space.md) {
                            Text(runtime.agent.displayName)
                            Spacer(minLength: DS.Space.md)
                            Text(runtime.status == .idle ? "Ready" : runtime.status.label)
                                .font(.dsCaption)
                                .foregroundStyle(.dsTextTertiary)
                            Image(systemName: "checkmark").font(DS.ComposerSettings.rowFont)
                                .opacity(entry.agent == runtime.agent.id ? 1 : 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!runtime.isAvailable)
                    .dsHitTarget(DS.Size.controlSM)
                    if entry.device == .thisMac, runtime.status.canRetry {
                        Button("Retry") { Task { await model.restart(runtime.agent.id) } }
                            .buttonStyle(.ds(.secondary))
                    }
                }
                .font(.dsCallout)
                .foregroundStyle(.dsTextPrimary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.xs)
            }
            if model.quickEntryRuntimes.isEmpty {
                Text("No agents are available on this device. Choose another device or add an agent.")
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(DS.Space.lg)
            }
            if entry.device == .thisMac {
                SeparatorLine()
                Button("Add Agent…") { model.isAddingAgent = true }
                    .buttonStyle(.ds(.ghost))
                    .padding(DS.Space.xs)
            }
        }
        .padding(DS.Space.xs)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Project").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Button {
                    model.chooseNoProject()
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "checkmark").font(DS.ComposerSettings.rowFont)
                            .opacity(entry.project == nil ? 1 : 0)
                            .frame(width: DS.ComposerSettings.selectionWidth)
                        Text("No project").font(DS.ComposerSettings.rowFont)
                        Spacer(minLength: DS.Space.sm)
                    }
                    .padding(.horizontal, DS.Space.xs)
                    .frame(height: DS.ComposerSettings.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(entry.project == nil ? .isSelected : [])
                SeparatorLine().padding(.vertical, DS.Space.xs)
                ForEach(model.projects.all) { project in
                    Button {
                        model.chooseQuickEntryProject(project.id)
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: "checkmark").font(DS.ComposerSettings.rowFont)
                                .opacity(entry.project == project.id ? 1 : 0)
                                .frame(width: DS.ComposerSettings.selectionWidth)
                            Text(project.name).font(DS.ComposerSettings.rowFont)
                            Spacer(minLength: DS.Space.sm)
                        }
                        .padding(.horizontal, DS.Space.xs)
                        .frame(height: DS.ComposerSettings.rowHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.dsTextPrimary)
                    .background(
                        entry.project == project.id ? Color.dsSelected : .clear,
                        in: .rect(cornerRadius: DS.Radius.control)
                    )
                    .accessibilityAddTraits(entry.project == project.id ? .isSelected : [])
                }
                SeparatorLine().padding(.vertical, DS.Space.xs)
                Button {
                    entry.isChoosingFolder = true
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "folder").font(DS.ComposerSettings.rowFont).foregroundStyle(.dsTextSecondary)
                            .frame(width: DS.ComposerSettings.selectionWidth)
                        Text("Choose a Folder…").font(DS.ComposerSettings.rowFont)
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
        .padding(DS.ComposerSettings.sectionInset)
        .padding(DS.ComposerSettings.popoverInset)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Quick Entry - Device picker") {
    QuickEntryPreviewFixture(state: .devices)
}
#Preview("Quick Entry - Agent picker") {
    QuickEntryPreviewFixture(state: .agents)
}
#Preview("Quick Entry - Project picker") {
    QuickEntryPreviewFixture(state: .projects)
}
#endif
