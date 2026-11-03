import ACP
import SwiftUI

struct ComposerAgentModelMenu: View {
    let agents: [ComposerRowState.Agent]
    let effort: [ComposerRowState.Choice]
    var notice: String?
    let chooseModel: (String) -> Void
    let chooseEffort: (String) -> Void
    let chooseSetting: (String, String) -> Void
    let close: () -> Void
    @State private var query = ""

    init(
        agents: [ComposerRowState.Agent], effort: [ComposerRowState.Choice], notice: String? = nil,
        query: String = "", chooseModel: @escaping (String) -> Void, chooseEffort: @escaping (String) -> Void,
        chooseSetting: @escaping (String, String) -> Void = { _, _ in },
        close: @escaping () -> Void
    ) {
        self.agents = agents
        self.effort = effort
        self.notice = notice
        self.chooseModel = chooseModel
        self.chooseEffort = chooseEffort
        self.chooseSetting = chooseSetting
        self.close = close
        _query = State(initialValue: query)
    }

    private var showsSearch: Bool {
        agents.reduce(0) { $0 + $1.models.count } > DS.ComposerRow.searchThreshold
    }

    private var filteredAgents: [ComposerRowState.Agent] {
        let filter = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return agents }
        return agents.compactMap { agent in
            var result = agent
            result.models = agent.models.filter {
                "\(agent.name) \($0.title) \($0.detail)".localizedStandardContains(filter)
            }
            return result.models.isEmpty ? nil : result
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if showsSearch {
                SearchField("Search agents and models", text: $query)
                    .padding(DS.Space.sm)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(filteredAgents) { agent in
                        Text(agent.name)
                            .font(.dsCaption).foregroundStyle(.dsTextSecondary)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.top, DS.Space.md)
                        ForEach(agent.models) { model in
                            HStack(spacing: DS.Space.xs) {
                                ComposerRowMenuOption(choice: model) { chooseModel(model.id) }
                                if model.isSelected, !effort.isEmpty {
                                    effortMenu
                                }
                            }
                        }
                        if !agent.settings.isEmpty {
                            Divider().padding(.horizontal, DS.Space.md)
                            ForEach(agent.settings, id: \.option.id) { setting in
                                settingMenu(setting)
                            }
                        }
                    }
                    if filteredAgents.isEmpty {
                        Text(
                            agents.isEmpty
                                ? "No agents available. Check Agents in Settings."
                                : "No matching models. Try another name."
                        )
                        .font(.dsBody).foregroundStyle(.dsTextSecondary)
                        .padding(DS.Space.lg)
                    }
                }
            }
            .frame(maxHeight: DS.ComposerRow.menuMaxHeight)
            if let notice {
                Text(notice).font(.dsCaption).foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(DS.Space.md)
            }
        }
        .padding(DS.Space.sm)
        .frame(width: DS.ComposerRow.menuWidth)
        .background(.dsOverlay)
        .onKeyPress(.escape) {
            if query.isEmpty { close() } else { query = "" }
            return .handled
        }
    }

    private var effortMenu: some View {
        Menu {
            ForEach(effort) { choice in
                Button {
                    chooseEffort(choice.id)
                } label: {
                    Label(choice.title, systemImage: choice.isSelected ? "checkmark" : "circle")
                }
                .disabled(choice.unavailable != nil)
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(effort.first(where: \.isSelected)?.title ?? "Effort")
                Image(systemName: "chevron.down").font(.dsMicro)
            }
            .font(.dsCaption)
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: DS.ComposerRow.menuRowHeight)
        }
        .menuStyle(.button).buttonStyle(ComposerRowControlStyle()).menuIndicator(.hidden).fixedSize()
        .padding(.trailing, DS.Space.md)
        .accessibilityLabel("Model effort")
        .accessibilityValue(effort.first(where: \.isSelected)?.title ?? "Default")
    }

    private func settingMenu(_ setting: SelectSetting) -> some View {
        Menu {
            ForEach(setting.choices) { choice in
                Button {
                    chooseSetting(setting.option.id, choice.value)
                } label: {
                    Label(choice.name, systemImage: choice.value == setting.value ? "checkmark" : "circle")
                }
                .help(choice.description ?? choice.name)
            }
        } label: {
            HStack(spacing: DS.Space.md) {
                Text(setting.option.name)
                    .font(.dsBody).foregroundStyle(.dsTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(setting.currentName).font(.dsCaption).lineLimit(1)
                Image(systemName: "chevron.down").font(.dsMicro)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.leading, DS.ComposerRow.checkWidth + DS.Space.md)
            .frame(minHeight: DS.ComposerRow.menuRowHeight)
            .contentShape(.rect)
        }
        .menuStyle(.button).buttonStyle(ComposerRowControlStyle()).menuIndicator(.hidden)
        .disabled(setting.choices.isEmpty)
        .accessibilityLabel(setting.option.name)
        .accessibilityValue(setting.currentName)
        .help(setting.option.description ?? setting.option.name)
    }
}

#if DEBUG
#Preview("Composer agent menu - All agents and inline effort") {
    DSPreviewPair { ComposerRowPreviewFixtures.agentMenu() }
}

#Preview("Composer agent menu - With and without extra options") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            ComposerRowPreviewFixtures.agentMenu(extraOptions: true)
            ComposerRowPreviewFixtures.agentMenu(shortList: true)
        }
    }
}
#endif
