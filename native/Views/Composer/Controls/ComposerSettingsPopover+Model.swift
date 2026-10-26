import ACP
import SwiftUI

extension ComposerSettingsPopover {
    var modelList: ModelChoiceList? {
        if let agentModels {
            let compact = needsCompactModelList
            return ModelChoiceList(
                choices: agentModels.map(\.listChoice), current: currentModelID ?? "", query: query,
                slots: compact ? 5 : ModelChoiceList.slots,
                searchTerms: Dictionary(uniqueKeysWithValues: agentModels.map { ($0.id, $0.searchTerms) }),
                forceFilter: compact)
        }
        return settings.model.map { ModelChoiceList(choices: $0.choices, current: $0.value, query: query) }
    }

    var currentModelID: String? {
        guard let agentModels else { return settings.model?.value }
        return agentModels.first {
            $0.agent == currentAgentID && $0.kind == .model(settings.model?.value)
        }?.id
    }

    /// Reserve the full caption, footer and task rows before allocating model slots.
    var needsCompactModelList: Bool {
        guard let agentModels else { return false }
        let count = agentModels.count > ModelChoiceList.filterThreshold ? ModelChoiceList.slots : agentModels.count
        if page == .model {
            return CGFloat(count + 1) * DS.ComposerSettings.rowHeight
                + DS.ComposerSettings.modelCaptionHeight + DS.ComposerSettings.sectionInset * 2
                + DS.ComposerSettings.popoverInset * 2 > DS.ComposerSettings.popoverMaxHeight
        }
        return estimatedSettingsHeight(models: count) > DS.ComposerSettings.popoverMaxHeight
    }

    var omitsModelCaptions: Bool {
        agentModels != nil && page != .model && needsCompactModelList
            && estimatedSettingsHeight(models: 5) > DS.ComposerSettings.popoverMaxHeight
    }

    private func estimatedSettingsHeight(models: Int) -> CGFloat {
        let autonomy = settings.autonomy == nil ? 0 : settings.autonomyLevels.count + 2
        let effort = settings.effort == nil ? 0 : 1
        let footer = manager == nil ? 0 : DS.ComposerSettings.managedFooterReserve
        let empty =
            agentModels?.contains { $0.agent != currentAgentID } == true
            ? 0 : DS.ComposerSettings.emptyModelsReserve
        return CGFloat(models + autonomy + effort + rows.count) * DS.ComposerSettings.rowHeight
            + DS.ComposerSettings.sectionsReserve + footer + empty
    }

    var hasOtherAgentModels: Bool {
        agentModels?.contains { $0.agent != currentAgentID && $0.unavailable == nil } == true
    }

    var modelTargets: [Target] {
        modelList?.rows.compactMap { row in
            if let entry = agentModels?.first(where: { $0.id == row.id }),
                entry.unavailable != nil || (isStopped && entry.agent == currentAgentID)
            {
                return nil
            }
            return .model(row.id)
        } ?? []
    }

    /// The Fast mode switch, on the Model header's trailing edge.
    var fastMode: SelectSetting? {
        settings.modelSwitches.first
    }

    var modelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agentModels != nil {
                if DS.isTouchPlatform {
                    Button {
                        page = .model
                    } label: {
                        ComposerSettingsRow(highlight: highlight(of: .model(currentModelID ?? ""))) {
                            Text("Model")
                        } trailing: {
                            ComposerSettingsValue(
                                text: settings.model?.shortModelName ?? "Default", glyph: "chevron.right")
                        }
                    }.buttonStyle(.plain)
                } else {
                    agentModelRows()
                }
            } else if let model = settings.model {
                if DS.isTouchPlatform {
                    modelPageRow(model)
                } else {
                    modelRows(model)
                }
            } else {
                Text("\(agentName) picks its own model.")
                    .font(DS.ComposerSettings.rowFont)
                    .foregroundStyle(.dsTextTertiary)
                    .composerSettingsTextEdge()
                    .frame(height: DS.ComposerSettings.rowHeight)
            }
            if let effort = settings.effort {
                ComposerSettingsEffortLine(
                    effort: effort, isEnabled: !isStopped, isKeyboardFocused: highlighted == .effort
                ) { onSet(effort, $0) }
            }
        }
    }

    /// On touch the list is a page of its own; the door shows the model it's on.
    private func modelPageRow(_ model: SelectSetting) -> some View {
        Button {
            page = .model
        } label: {
            ComposerSettingsRow(highlight: highlight(of: .model(model.value)), isDimmed: isStopped) {
                Text("Model")
            } trailing: {
                ComposerSettingsValue(text: model.shortModelName, glyph: "chevron.right")
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(model.shortModelName)
        .accessibilityHint("Opens a page")
    }

    /// The models: a header, or past eight a filter in its place, the rows and their caption. On the
    /// touch page the page's own header names the list.
    @ViewBuilder func modelRows(_ model: SelectSetting, isPage: Bool = false) -> some View {
        let list = ModelChoiceList(choices: model.choices, current: model.value, query: query)
        if list.isFilterable {
            filterLine(count: model.choices.uniqued.count)
        } else if !isPage {
            ComposerSettingsHeader(title: "Model") { fastModeSwitch }
        } else if fastMode != nil {
            HStack {
                Spacer()
                fastModeSwitch
            }
            .composerSettingsTextEdge()
            .frame(height: DS.ComposerSettings.rowHeight)
        }
        ForEach(list.rows) { row in
            modelRow(row, setting: model, isFirstMatch: !list.query.isEmpty && row.id == list.rows.first?.id)
        }
        if list.isFilterable {
            filterFooter(list)
        }
        if !isStopped { modelCaption(model, list: list) }
    }

    private func modelRow(_ row: ModelChoiceList.Row, setting: SelectSetting, isFirstMatch: Bool) -> some View {
        let target = Target.model(row.id)
        let lit = highlight(of: target)
        return Button {
            choose(target, closing: false)
        } label: {
            ComposerSettingsRow(
                mark: mark(for: setting, value: row.id, isCurrent: row.id == setting.value),
                highlight: lit == .none && isFirstMatch && highlighted == nil ? .match : lit,
                isDimmed: isStopped
            ) {
                Text(Self.marked(row.name, row.nameMatches, font: DS.ComposerSettings.rowMatchFont))
            } trailing: {
                switch row.detail {
                case .note(let note):
                    Text(note)
                        .font(DS.ComposerSettings.detailFont)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                case .value(let value, let matches):
                    Text(Self.marked(value, matches, font: .dsMonoCaption, color: .dsTextPrimary))
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                case nil:
                    EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
        .composerSettingsHover(target, hovered: $hovered)
        .help([row.choice.description, row.choice.value].compactMap { $0 }.joined(separator: "\n"))
        .contextMenu {
            Button("Copy Model ID") { DSPasteboard.copy(row.choice.value) }
        }
        .accessibilityLabel(row.name)
        .accessibilityHint(row.choice.description ?? "")
        .accessibilityAddTraits(row.id == setting.value ? .isSelected : [])
        .accessibilityAction(named: "Copy Model ID") { DSPasteboard.copy(row.choice.value) }
    }

    /// The name or value with the filter's matches drawn heavier.
    static func marked(
        _ text: String, _ matches: [Range<String.Index>], font: Font, color: Color? = nil
    ) -> AttributedString {
        var marked = AttributedString(text)
        for match in matches {
            guard let lower = AttributedString.Index(match.lowerBound, within: marked),
                let upper = AttributedString.Index(match.upperBound, within: marked)
            else { continue }
            marked[lower..<upper].font = font
            if let color { marked[lower..<upper].foregroundColor = color }
        }
        return marked
    }

    // MARK: - Filter

    func filterLine(count: Int) -> some View {
        HStack(spacing: DS.Space.md) {
            SearchField(
                "Filter models", text: $query, prompt: Text("Filter \(count) models"), font: DS.ComposerSettings.rowFont
            ) {
                EmptyView()
            }
            .searchFieldStyle(.inline)
            .focused($isFilterFocused)
            .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
            .onChange(of: query) { highlighted = nil }
            if !query.isEmpty {
                Kbd("esc")
            }
            fastModeSwitch
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: DS.ComposerSettings.rowHeight)
        .padding(.horizontal, DS.ComposerSettings.popoverInset)
        .padding(.bottom, DS.Space.xxs)
        .accessibilityValue("\(count) models")
    }

    /// The slots a filtered list keeps, so typing never changes the popover's height: what didn't
    /// fit, or that nothing matched.
    @ViewBuilder func filterFooter(_ list: ModelChoiceList) -> some View {
        let used = list.rows.count + (list.overflow > 0 || list.rows.isEmpty ? 1 : 0)
        if list.overflow > 0 {
            slotNote("\(list.overflow) more match. Keep typing.")
        } else if list.rows.isEmpty {
            HStack(spacing: DS.Space.sm) {
                Text("No model named “\(query)”.")
                Kbd("esc")
                Text("clears it.")
            }
            .modifier(SlotNote())
        }
        ForEach(0..<max((needsCompactModelList ? 5 : ModelChoiceList.slots) - used, 0), id: \.self) { _ in
            Color.clear.frame(height: DS.ComposerSettings.rowHeight)
        }
    }

    private func slotNote(_ text: String) -> some View {
        Text(text).modifier(SlotNote())
    }

    private func modelCaption(_ model: SelectSetting, list: ModelChoiceList) -> some View {
        let failed = failure.flatMap { [model.option.id, settings.effort?.option.id].contains($0.optionID) ? $0 : nil }
        let shown = list.rows.map(\.choice) + (model.current.map { [$0] } ?? [])
        let purposes = shown.compactMap(Self.caption(of:))
        let previewed: SelectSetting.Choice? =
            switch highlighted ?? hovered ?? firstMatch {
            case .model(let value): model.choices.first { $0.value == value }
            default: nil
            }
        let text = failed.map(\.message) ?? (previewed ?? model.current).flatMap(Self.caption(of:))
        return Group {
            if failed != nil || !purposes.isEmpty {
                ComposerSettingsCaption(
                    text: text.map { AttributedString($0) }, reserving: purposes.map { AttributedString($0) },
                    isFailure: failed != nil, isKeyboardFocused: highlighted == .retry,
                    action: failed?.retry.map { ComposerSettingsTaskRow.Command(title: "Try Again", action: $0) })
            }
        }
    }

    /// A model's line under the list: its purpose, but not Default's (its row already says what it runs).
    static func caption(of choice: SelectSetting.Choice) -> String? {
        choice.resolvedDefault == nil ? choice.purpose : nil
    }

    @ViewBuilder var fastModeSwitch: some View {
        if let fastMode {
            HStack(spacing: DS.Space.md) {
                Text(fastMode.option.name)
                    .font(DS.ComposerSettings.detailFont)
                    .foregroundStyle(.dsTextSecondary)
                Toggle(
                    fastMode.option.name,
                    isOn: Binding(get: { fastMode.isOn }, set: { onSet(fastMode, $0 ? "on" : "off") })
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(DS.isTouchPlatform ? .regular : .mini)
            }
            .composerSettingsCommandFocus(highlighted == .fastMode)
            .disabled(isStopped)
        }
    }

    // MARK: - Pages

    /// The model list on its own page (touch).
    var modelPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerSettingsPageHeader(title: "Model", isKeyboardFocused: highlighted == .back) { page = nil }
            if agentModels != nil {
                agentModelRows(isPage: true)
            } else if let model = settings.model {
                modelRows(model, isPage: true)
            }
        }
        .padding(.bottom, DS.ComposerSettings.sectionInset)
    }
}

/// A line that sits in a row slot: overflow and no-match.
private struct SlotNote: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.ComposerSettings.detailFont)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
            .frame(height: DS.ComposerSettings.rowHeight)
            .composerSettingsTextEdge()
    }
}
