import ACP
import SwiftUI

/// The one settings door. Choices stay together while agent updates replace the offered values.
struct ComposerSettingsPopover<Connections: View, Actions: View>: View {
    let settings: ComposerSettings
    let agentName: String
    var manager: String?
    var permissionsManaged = false
    var forbiddenModes: Set<String> = []
    var isApplying = false
    var failure: String?
    var source: (ConfigOption) -> SettingsSourceLabel.Source
    let onSet: (SelectSetting, String) -> Void
    @ViewBuilder let connections: () -> Connections
    @ViewBuilder let actions: () -> Actions

    @State private var modelQuery = ""

    var body: some View {
        CappedHeightScrollView(maxHeight: DS.ComposerSettings.popoverMaxHeight) {
            VStack(alignment: .leading, spacing: 0) {
                modelSection
                if let effort = settings.effort { effortSection(effort) }
                if let autonomy = settings.autonomy { autonomySection(autonomy) }
                section {
                    connections()
                    ForEach(settings.modelSwitches + settings.others, id: \.option.id) { setting in
                        settingRow(setting)
                    }
                }
                section { actions() }
                if let failure {
                    Text(failure)
                        .font(DS.ComposerSettings.detailFont)
                        .foregroundStyle(.dsDanger)
                        .padding(DS.ComposerSettings.sectionInset)
                        .accessibilityIdentifier("composer-settings-failure")
                }
                if let manager {
                    SeparatorLine()
                    Label("Managed by \(manager).", systemImage: "lock")
                        .font(DS.ComposerSettings.detailFont)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DS.ComposerSettings.sectionInset)
                }
            }
            .padding(DS.ComposerSettings.popoverInset)
        }
        .frame(width: DS.ComposerSettings.popoverWidth)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            heading("Model", option: settings.model?.option)
            if let model = settings.model {
                if model.choices.count > 6 {
                    SearchField("Search models", text: $modelQuery)
                }
                CappedHeightScrollView(maxHeight: DS.ComposerSettings.modelListHeight) {
                    VStack(spacing: 0) {
                        let matches = model.choices(matching: modelQuery)
                        if matches.isEmpty {
                            Text("No models match “\(modelQuery)”")
                                .font(.dsBody)
                                .foregroundStyle(.dsTextTertiary)
                                .padding(.vertical, DS.Space.sm)
                        }
                        ForEach(matches) { choice in
                            modelRow(choice, setting: model)
                        }
                    }
                }
            } else {
                Text("\(agentName) chooses its own model.")
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
            }
        }
        .padding(DS.ComposerSettings.sectionInset)
    }

    private func modelRow(_ choice: SelectSetting.Choice, setting: SelectSetting) -> some View {
        let selected = setting.value == choice.value
        return Button {
            onSet(setting, choice.value)
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "checkmark")
                    .opacity(selected ? 1 : 0)
                    .frame(width: DS.ComposerSettings.selectionWidth)
                Text(setting.displayName(of: choice))
                    .font(DS.ComposerSettings.rowFont)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: DS.Space.sm)
                Text(choice.value)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, DS.Space.xs)
            .frame(minHeight: DS.ComposerSettings.rowHeight)
            .background(selected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.dsTextPrimary)
        .disabled(isApplying)
        .dsHitTarget(DS.ComposerSettings.controlHeight)
        .help(choice.description ?? choice.name)
        .accessibilityLabel(setting.displayName(of: choice))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func effortSection(_ effort: SelectSetting) -> some View {
        section {
            heading("Effort", option: effort.option)
            ViewThatFits(in: .horizontal) {
                Picker("Effort", selection: binding(effort)) {
                    ForEach(effort.choices) { choice in Text(choice.name).tag(choice.value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .controlSize(.small)
                Picker("Effort", selection: binding(effort)) {
                    ForEach(effort.choices) { choice in Text(choice.name).tag(choice.value) }
                }
                .labelsHidden()
            }
            .disabled(isApplying)
        }
    }

    private func autonomySection(_ autonomy: SelectSetting) -> some View {
        section {
            heading("When \(agentName) asks", option: autonomy.option, managed: permissionsManaged)
            ForEach(autonomy.choices) { choice in
                let locked = forbiddenModes.contains(choice.value)
                let selected = choice.value == autonomy.value
                Button {
                    onSet(autonomy, choice.value)
                } label: {
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        Image(systemName: locked ? "lock" : selected ? "smallcircle.filled.circle.fill" : "circle")
                            .frame(width: DS.ComposerSettings.selectionWidth)
                            .padding(.top, DS.Space.xxs)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(choice.askingTitle).font(DS.ComposerSettings.rowFont)
                            if let detail = AutonomySummary.summary(of: choice) {
                                Text(detail)
                                    .font(DS.ComposerSettings.detailFont)
                                    .foregroundStyle(.dsTextTertiary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.xs)
                    .padding(.vertical, DS.Space.sm)
                    .background(selected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(locked ? .dsTextTertiary : .dsTextPrimary)
                .disabled(locked || isApplying)
                .dsHitTarget(DS.ComposerSettings.controlHeight)
                .accessibilityLabel(choice.askingTitle)
                .accessibilityHint(AutonomySummary.summary(of: choice) ?? "")
                .accessibilityValue(
                    locked ? "Not allowed by \(manager ?? "your organization")" : selected ? "Selected" : ""
                )
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func settingRow(_ setting: SelectSetting) -> some View {
        Menu {
            Picker(setting.option.name, selection: binding(setting)) {
                ForEach(setting.choices) { choice in
                    Text(choice.name).tag(choice.value)
                }
            }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: setting.option.category == "web_search" ? "globe" : "terminal")
                    .foregroundStyle(.dsTextTertiary)
                Text(setting.option.name)
                Spacer(minLength: DS.Space.sm)
                Text(setting.currentName).foregroundStyle(.dsTextSecondary)
                SettingsSourceLabel(source: source(setting.option))
                Image(systemName: "chevron.right").font(.dsMicro).foregroundStyle(.dsTextTertiary)
            }
            .font(DS.ComposerSettings.rowFont)
            .frame(minHeight: DS.ComposerSettings.rowHeight)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(isApplying)
        .dsHitTarget(DS.ComposerSettings.controlHeight)
        .accessibilityLabel(setting.option.name)
        .accessibilityValue(setting.currentName)
        .help(setting.option.description ?? setting.option.name)
    }

    private func heading(_ title: String, option: ConfigOption?, managed: Bool = false) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(title).font(.dsCaption).foregroundStyle(.dsTextTertiary)
            Spacer(minLength: DS.Space.sm)
            if managed, let manager {
                SettingsSourceLabel(source: .organization(manager))
            } else if let option {
                SettingsSourceLabel(source: source(option))
            }
        }
    }

    private func section(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SeparatorLine()
            VStack(alignment: .leading, spacing: DS.Space.xs, content: content)
                .padding(DS.ComposerSettings.sectionInset)
        }
    }

    private func binding(_ setting: SelectSetting) -> Binding<String> {
        Binding(get: { setting.value }, set: { onSet(setting, $0) })
    }
}

#if DEBUG
#Preview("Task settings - Available, managed, empty and failure") {
    DSPreviewPair {
        HStack(alignment: .top) {
            ForEach(0..<4) { state in
                ComposerSettingsPopover(
                    settings: state == 2 ? ComposerSettings([]) : ComposerPreviewFixtures.settings,
                    agentName: "Claude Code", manager: state == 1 ? "Northwind Federal IT" : nil,
                    permissionsManaged: state == 1,
                    forbiddenModes: state == 1 ? ["auto", "bypassPermissions", "acceptEdits"] : [],
                    failure: state == 3 ? "Couldn't change Effort. High is still selected. Try again." : nil,
                    source: { _ in .agent("Claude Code") }, onSet: { _, _ in }
                ) {
                    Text("MCP servers").font(.dsBody)
                } actions: {
                    Text("Attach Files…").font(.dsBody)
                }
                .dsPopoverBackground()
            }
        }
    }
}
#endif
