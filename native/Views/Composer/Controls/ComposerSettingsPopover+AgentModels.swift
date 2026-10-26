import ACP
import SwiftUI

extension ComposerSettingsPopover {
    var offersAgentsSettings: Bool {
        guard let agentModels, onAgentsSettings != nil else { return false }
        return agentModels.allSatisfy { $0.agent == currentAgentID }
    }

    @ViewBuilder func agentModelRows(isPage: Bool = false) -> some View {
        if let list = modelList, let agentModels {
            if list.isFilterable {
                filterLine(count: agentModels.count)
            } else if !isPage {
                ComposerSettingsHeader(title: "Model") { fastModeSwitch }
            }
            ForEach(list.rows) { row in
                if let entry = agentModels.first(where: { $0.id == row.id }) {
                    agentModelRow(entry, row: row, first: !list.query.isEmpty && list.rows.first?.id == row.id)
                }
            }
            if list.isFilterable { filterFooter(list) }
            if offersAgentsSettings, let onAgentsSettings {
                HStack(spacing: DS.Space.sm) {
                    Text("No other agent is ready.")
                    Button("Agents Settings…", action: onAgentsSettings).buttonStyle(.plain)
                        .foregroundStyle(.dsTextPrimary)
                        .composerSettingsCommandFocus(highlighted == .agentsSettings)
                        .dsHitTarget(DS.ComposerSettings.lineHeight)
                }
                .font(DS.ComposerSettings.detailFont)
                .foregroundStyle(.dsTextSecondary)
                .composerSettingsTextEdge()
                .padding(.vertical, DS.Space.sm)
            }
            agentModelCaption
        }
    }

    private func agentModelRow(
        _ entry: ComposerAgentModel, row: ModelChoiceList.Row, first: Bool
    ) -> some View {
        let target = Target.model(entry.id)
        let lit = highlight(of: target)
        let selected = entry.id == currentModelID
        let starting =
            (modelChange?.stage == .preparing && modelChange?.showsLoader == true
                && modelChange?.choice.id == entry.id) || loadingModelID == entry.id
        let changingCurrent =
            entry.agent == currentAgentID && pending?.optionID == settings.model?.option.id
            && pending != nil
        let ordinaryLoader = changingCurrent && pending?.value == entry.choice.value
        let mark: ComposerSettingsMark =
            entry.isManaged
            ? .lock
            : starting || ordinaryLoader
                ? .loading
                : changingCurrent ? .none : selected ? .check : .none
        let stopped = isStopped && entry.agent == currentAgentID
        return Button {
            choose(target, closing: false)
        } label: {
            ComposerSettingsRow(
                mark: mark, highlight: lit == .none && first && highlighted == nil ? .match : lit,
                isDimmed: entry.unavailable != nil || stopped
            ) {
                Text(Self.marked(row.name, row.nameMatches, font: DS.ComposerSettings.rowMatchFont))
            } trailing: {
                Text(entry.agentName + (entry.isManaged ? " · Not allowed" : ""))
                    .font(DS.ComposerSettings.detailFont)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        // Unavailable rows still preview their recovery caption under the pointer and in VoiceOver.
        .disabled(entry.unavailable != nil || stopped)
        .composerSettingsHover(target, hovered: $hovered)
        .help(
            [entry.choice.description, entry.choice.value, entry.agentName, entry.unavailable]
                .compactMap { $0 }.joined(separator: "\n")
        )
        .accessibilityLabel("\(entry.choice.displayName), \(entry.agentName)")
        .accessibilityValue(
            entry.isManaged
                ? "Not allowed by \(manager ?? "your organization")"
                : starting ? "Starting" : entry.unavailable ?? ""
        )
        .accessibilityHint(entry.agent == currentAgentID ? entry.choice.purpose ?? "" : entry.caption)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var agentModelCaption: some View {
        let rowID: String? =
            switch highlighted ?? hovered ?? firstMatch {
            case .model(let id): id
            default: currentModelID
            }
        let entry = agentModels?.first { $0.id == rowID }
        let modelFailure = failure.flatMap {
            ["agent-model", settings.model?.option.id, settings.effort?.option.id].contains($0.optionID) ? $0 : nil
        }
        let failed = modelChange?.stage == .failed ? modelChange?.error : modelFailure?.message
        let text: String? =
            if let failed {
                failed
            } else if modelChange?.stage == .preparing || loadingModelID != nil {
                "Starting \(modelChange?.choice.agentName ?? agentModels?.first(where: { $0.id == loadingModelID })?.agentName ?? "the agent"). Your task and draft are kept."
            } else if let entry, entry.agent != currentAgentID {
                entry.caption
            } else if let reason = entry?.unavailable {
                reason
            } else {
                settings.model == nil ? "\(agentName) picks its own model." : entry?.choice.purpose
            }
        return ComposerSettingsCaption(
            text: text.map { AttributedString($0) }, isFailure: failed != nil,
            isKeyboardFocused: highlighted == .retry,
            action: modelFailure?.retry.map { .init(title: "Try Again", action: $0) }
        )
        .frame(minHeight: DS.ComposerSettings.modelCaptionHeight, alignment: .topLeading)
    }
}
