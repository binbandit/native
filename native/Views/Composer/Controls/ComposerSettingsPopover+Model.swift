import ACP
import SwiftUI

extension ComposerSettingsPopover {
    var modelList: ModelChoiceList? { modelList(slots: modelSlots) }

    func modelList(slots: Int) -> ModelChoiceList? {
        if let agentModels {
            return ModelChoiceList(
                choices: agentModels.map(\.listChoice), current: currentModelID ?? "", query: query,
                slots: page == .model
                    ? (agentModels.count > ModelChoiceList.filterThreshold ? ModelChoiceList.slots : agentModels.count)
                    : slots,
                searchTerms: Dictionary(uniqueKeysWithValues: agentModels.map { ($0.id, $0.searchTerms) }))
        }
        return settings.model.map {
            ModelChoiceList(
                choices: $0.choices, current: $0.value, query: query,
                slots: page == .model
                    ? ($0.choices.count > ModelChoiceList.filterThreshold ? ModelChoiceList.slots : $0.choices.count)
                    : slots)
        }
    }

    var currentModelID: String? {
        guard let agentModels else { return settings.model?.value }
        return agentModels.first {
            $0.agent == currentAgentID && $0.kind == .model(settings.model?.value)
        }?.id
    }

    var hasOtherAgentModels: Bool {
        agentModels?.contains { $0.agent != currentAgentID && $0.unavailable == nil } == true
    }

    var modelTargets: [Target] {
        let targets: [Target] =
            modelList?.rows.compactMap { row in
                if let entry = agentModels?.first(where: { $0.id == row.id }),
                    entry.unavailable != nil || (isStopped && entry.agent == currentAgentID)
                {
                    return nil
                }
                if isStopped && agentModels == nil { return nil }
                return .model(row.id)
            } ?? []
        return targets + (modelList.map { !$0.isFilterable && $0.overflow > 0 } == true ? [.moreModels] : [])
    }

    /// The Fast mode switch, on the Model header's trailing edge.
    var fastMode: SelectSetting? {
        settings.modelSwitches.first
    }

    func modelSection(slots: Int, showsCaption: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if agentModels != nil {
                if DS.isTouchPlatform {
                    modelPageRow(settings.model)
                } else {
                    agentModelRows(slots: slots, showsCaption: showsCaption)
                }
            } else if let model = settings.model {
                if DS.isTouchPlatform {
                    modelPageRow(model)
                } else {
                    modelRows(model, slots: slots, showsCaption: showsCaption)
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
    private func modelPageRow(_ model: SelectSetting?) -> some View {
        Button {
            page = .model
        } label: {
            ComposerSettingsRow(highlight: highlight(of: .model(currentModelID ?? "")), isDimmed: isStopped) {
                Text("Model")
            } trailing: {
                ComposerSettingsValue(text: model?.shortModelName ?? "Default", glyph: "chevron.right")
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(model?.shortModelName ?? "Default")
        .accessibilityHint("Opens a page")
    }

    /// The models: a header, or past eight a filter in its place, the rows and their caption. On the
    /// touch page the page's own header names the list.
    @ViewBuilder func modelRows(
        _ model: SelectSetting, isPage: Bool = false, slots: Int = ModelChoiceList.slots, showsCaption: Bool = true
    ) -> some View {
        let list = modelList(slots: slots) ?? ModelChoiceList(choices: [], current: "")
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
        modelOverflow(list, slots: slots)
        if !isStopped && (showsCaption || failure != nil) { modelCaption(model) }
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
        .disabled(isStopped)
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
    @ViewBuilder func filterFooter(_ list: ModelChoiceList, slots: Int = ModelChoiceList.slots) -> some View {
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
        ForEach(0..<max(slots - used, 0), id: \.self) { _ in
            Color.clear.frame(height: DS.ComposerSettings.rowHeight)
        }
    }

    @ViewBuilder func modelOverflow(_ list: ModelChoiceList, slots: Int) -> some View {
        if list.isFilterable {
            filterFooter(list, slots: slots)
        } else if list.overflow > 0 {
            Button {
                page = .model
            } label: {
                ComposerSettingsRow(highlight: highlight(of: .moreModels)) {
                    Text("\(list.overflow) more models")
                        .font(DS.ComposerSettings.detailFont)
                        .foregroundStyle(.dsTextSecondary)
                } trailing: {
                    Image(systemName: "chevron.right").font(DS.ComposerSettings.glyphFont)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .buttonStyle(.plain)
            .composerSettingsHover(.moreModels, hovered: $hovered)
            .accessibilityHint("Opens the full model list")
        }
    }

    private func slotNote(_ text: String) -> some View {
        Text(text).modifier(SlotNote())
    }

    private func modelCaption(_ model: SelectSetting) -> some View {
        let failed = failure.flatMap { [model.option.id, settings.effort?.option.id].contains($0.optionID) ? $0 : nil }
        // Reserve from the entire section, independent of the query and the current choice.
        let purposes = model.choices.compactMap(Self.caption(of:))
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
            ComposerSettingsPageHeader(title: "Model", isKeyboardFocused: highlighted == .back) { leavePage() }
            if agentModels != nil {
                agentModelRows(isPage: true, slots: ModelChoiceList.slots, showsCaption: true)
            } else if let model = settings.model {
                modelRows(model, isPage: true)
            }
        }
        .padding(.bottom, DS.ComposerSettings.sectionInset)
        .onAppear { modelSlots = ModelChoiceList.slots }
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
