import ACP
import SwiftUI

/// The model list with a search field, after Factory's model dropdown (an agent can offer dozens of
/// models), plus the settings that tune the model: effort and switches such as Fast mode.
struct ModelPicker: View {
    let model: SelectSetting?
    let effort: SelectSetting?
    let switches: [SelectSetting]
    let onSet: (SelectSetting, String) -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var highlighted: Int?
    @FocusState private var isSearchFocused: Bool

    private var matches: [SelectSetting.Choice] {
        model?.choices(matching: query) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if model != nil {
                searchField
                SeparatorLine()
                list
            }
            if effort != nil || !switches.isEmpty {
                if model != nil {
                    SeparatorLine()
                }
                footer
            }
        }
        .frame(width: ComposerMetrics.modelPickerWidth)
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { highlighted = nil }
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onKeyPress(phases: [.down, .repeat]) { press in
                    handleKey(press)
                }
        }
        .font(.dsCallout)
        .padding(.horizontal, DS.Space.lg)
        .frame(height: ComposerMetrics.modelSearchHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            CappedHeightScrollView(maxHeight: ComposerMetrics.modelListMaxHeight) {
                VStack(spacing: 0) {
                    let matches = matches
                    if matches.isEmpty {
                        Text("No models match “\(query)”")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.md)
                            .frame(height: DS.Size.controlSM)
                    }
                    ForEach(matches.indices, id: \.self) { index in
                        row(matches[index], at: index)
                            .id(matches[index].value)
                    }
                }
                .padding(DS.Space.xs)
            }
            .onAppear {
                if let model {
                    proxy.scrollTo(model.value, anchor: .center)
                }
            }
            .onChange(of: highlighted) {
                if let highlighted, matches.indices.contains(highlighted) {
                    proxy.scrollTo(matches[highlighted].value)
                }
            }
        }
    }

    private func row(_ choice: SelectSetting.Choice, at index: Int) -> some View {
        let isCurrent = choice.value == model?.value
        return Button {
            choose(choice)
        } label: {
            // Like Factory's list, the current model is in the accent color.
            HStack(spacing: DS.Space.md) {
                Text(model?.displayName(of: choice) ?? choice.name)
                    .font(.dsCallout)
                    .foregroundStyle(isCurrent ? .dsAccentText : .dsTextPrimary)
                    .layoutPriority(1)
                if model?.isRecommended(choice) == true {
                    Badge("Recommended", tone: .neutral, style: .soft)
                }
                Spacer(minLength: 0)
                if let detail = model?.detail(of: choice) {
                    Text(detail)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // The accent can be monochrome, so the current model gets a check too.
                Image(systemName: "checkmark")
                    .font(.dsCaption)
                    .foregroundStyle(.dsAccentText)
                    .opacity(isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.Size.controlSM)
            .background(index == highlighted ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { highlighted = index }
        }
        .help(choice.description ?? choice.name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let effort {
                HStack {
                    Text(effort.option.name)
                    Spacer()
                    effortMenu(effort)
                }
            }
            ForEach(switches, id: \.option.id) { setting in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(setting.option.name)
                        // Carries why it's off when the agent can't serve it (Claude Code's Fast mode).
                        if let description = setting.option.description {
                            Text(description)
                                .font(.dsCaption)
                                .foregroundStyle(.dsTextTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Toggle(setting.option.name, isOn: Binding(get: { setting.isOn }, set: { onSet(setting, $0 ? "on" : "off") }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextPrimary)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    /// Effort levels with their cost noted beside each, as menu subtitles.
    private func effortMenu(_ effort: SelectSetting) -> some View {
        PillMenu(effort.currentName) {
            ForEach(effort.choices) { choice in
                Toggle(isOn: Binding(get: { choice.value == effort.value }, set: { _ in onSet(effort, choice.value) })) {
                    Text(choice.name)
                    if let note = effort.effortNote(for: choice) {
                        Text(note)
                    }
                }
            }
        }
        .help(effort.current.flatMap(effort.effortNote(for:)) ?? effort.option.name)
    }

    /// The search field keeps focus: arrows move through the list and Return picks.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Shortcuts with ⌘, ⌥ or ⌃ belong to the app and the text field.
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let matches = matches
        switch press.key {
        case .downArrow:
            highlighted = min((highlighted ?? -1) + 1, matches.count - 1)
            return .handled
        case .upArrow:
            highlighted = max((highlighted ?? matches.count) - 1, 0)
            return .handled
        case .return where press.phase == .down:
            // With nothing highlighted, Return takes the first match, as in Factory's picker.
            if let choice = highlighted.flatMap({ matches.indices.contains($0) ? matches[$0] : nil }) ?? matches.first {
                choose(choice)
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func choose(_ choice: SelectSetting.Choice) {
        if let model {
            onSet(model, choice.value)
        }
        dismiss()
    }
}
