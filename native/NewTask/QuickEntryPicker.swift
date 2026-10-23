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
                    onAddHost: openAddHost.map { action in { action() } }, width: nil
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
        return entry.project.map(model.deviceOptions(for:)) ?? []
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
                            Image(systemName: "checkmark")
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
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            heading("Project")
            ForEach(model.projects.all) { project in
                Button {
                    model.chooseQuickEntryProject(project.id)
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Text(project.name)
                        Spacer(minLength: DS.Space.md)
                        if entry.project == project.id { Image(systemName: "checkmark") }
                    }
                    .font(.dsCallout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.ds(.ghost))
                .dsHitTarget(DS.Size.controlSM)
            }
            SeparatorLine()
            Button("Choose a Folder…") { entry.isChoosingFolder = true }
                .buttonStyle(.ds(.ghost))
        }
        .padding(DS.Space.xs)
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
