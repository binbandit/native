import NativeCommands
import SwiftUI

/// The agent picker: a filter field over every agent, each with its icon, name and state, then Add
/// Agent and the keys along the bottom. It floats near the top of the window on the command
/// palette's surface, since it's the same kind of moment: one keyboard-first choice from a list.
///
/// It opens with the keyboard in the filter and the default agent highlighted. ↑ and ↓ move
/// between the agents that can start a session, Return starts it, typing narrows the list, and
/// Escape clears the filter, then closes (`docs/keyboard.md`, "Choosing an agent"). Every row is
/// also a button, for the pointer and touch; agents that can't start a session stay listed, dimmed,
/// with why and their fix.
///
/// The footer's trailing side says where the session starts. A choice of device belongs there too,
/// beside the project, when new sessions can pick one.
struct AgentPickerPanel<Notice: View>: View {
    let options: [AgentPickerOption]
    /// The project the session starts in, named in the footer.
    let projectName: String?
    /// Agents Native knows but can't find on this Mac, named on Add Agent's row; empty hides it.
    let missingAgents: [String]
    /// The shortcut that starts a session with the default agent (⌘N), shown on its row.
    let defaultShortcut: String?
    let onChoose: (AgentPickerOption) -> Void
    let onRemedy: (AgentPickerOption) async -> Void
    let onAddAgent: () -> Void
    let onDismiss: () -> Void
    /// Above the list: why no agent can start a session right now, with its fix.
    @ViewBuilder let notice: Notice

    private enum Field: Hashable {
        case filter
    }

    @State private var query = ""
    /// The row moved to with the keys or the pointer; nil until then, which means the default.
    @State private var highlighted: AgentPickerItem?
    @FocusState private var focus: Field?

    var body: some View {
        let results = AgentPickerResults(options: options, missingAgents: missingAgents, query: query)
        let current = current(in: results)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        VStack(spacing: 0) {
            filter(results, current: current)
                .padding(DS.Space.md)
            SeparatorLine()
            notice
            list(results, current: current)
            SeparatorLine()
            footer(current)
        }
        .frame(maxWidth: AgentPickerMetrics.width)
        .dsOverlayBackground(in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
        // After the field's own Escape, which clears what's typed first.
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onAppear { focus = .filter }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Session With")
        .accessibilityAddTraits(.isModal)
    }

    private func filter(_ results: AgentPickerResults, current: AgentPickerItem?) -> some View {
        SearchField(
            "Filter agents", text: $query, prompt: Text("New session with…"), size: .large, font: .dsCallout,
            focus: $focus, equals: .filter
        )
        .onKeyPress(.downArrow) { move(by: 1, in: results, from: current) }
        .onKeyPress(.upArrow) { move(by: -1, in: results, from: current) }
        // Emacs-style ⌃N and ⌃P, as in the command palette.
        .onKeyPress(keys: ["n", "p"]) { press in
            guard press.modifiers == .control else { return .ignored }
            return move(by: press.key == "n" ? 1 : -1, in: results, from: current)
        }
        .onKeyPress(.return) {
            if let current {
                activate(current, in: results)
            }
            return .handled
        }
        .onChange(of: query) { highlighted = nil }
    }

    private func list(_ results: AgentPickerResults, current: AgentPickerItem?) -> some View {
        ScrollViewReader { proxy in
            CappedHeightScrollView(maxHeight: AgentPickerMetrics.listMaxHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    if results.agents.isEmpty {
                        empty
                    }
                    ForEach(results.agents, id: \.option.id) { match in
                        AgentPickerRow(
                            option: match.option, isHighlighted: current == .agent(match.option.id),
                            highlights: match.highlights, defaultShortcut: defaultShortcut,
                            onChoose: { onChoose(match.option) }, onRemedy: { await onRemedy(match.option) }
                        )
                        .onHover { isHovering in
                            if isHovering, match.option.choice != nil { highlighted = .agent(match.option.id) }
                        }
                        .id(AgentPickerItem.agent(match.option.id))
                    }
                    if let missing = results.missingAgents {
                        if !results.agents.isEmpty {
                            SeparatorLine()
                                .padding(.vertical, DS.Space.xs)
                        }
                        AgentPickerAddRow(missingAgents: missing, isHighlighted: current == .addAgent) {
                            onAddAgent()
                        }
                        .onHover { if $0 { highlighted = .addAgent } }
                        .id(AgentPickerItem.addAgent)
                    }
                }
                .padding(DS.Space.xs)
            }
            .onChange(of: highlighted) {
                if let highlighted {
                    proxy.scrollTo(highlighted)
                }
            }
        }
    }

    private var empty: some View {
        Text("No agent matches \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.xl)
    }

    private func footer(_ current: AgentPickerItem?) -> some View {
        HStack(spacing: DS.Space.xl) {
            hint("↑↓", "Navigate")
            hint("↩", returnTitle(for: current))
            hint("esc", query.isEmpty ? "Close" : "Clear")
            Spacer(minLength: DS.Space.md)
            if let projectName {
                Text("Starts in \(Text(projectName).foregroundStyle(.dsTextSecondary))")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlMD)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Kbd(keys)
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func returnTitle(for item: AgentPickerItem?) -> String {
        switch item {
        case .addAgent: "Add Agent"
        case .agent(let id): options.first { $0.id == id }?.choice == .signInThenStart ? "Sign In" : "Start"
        case nil: "Start"
        }
    }

    /// The highlighted row: the one moved to while it's still listed and can be chosen, else the
    /// default agent (with nothing typed) or the best match.
    private func current(in results: AgentPickerResults) -> AgentPickerItem? {
        let items = results.items
        if let highlighted, items.contains(highlighted) { return highlighted }
        if query.isEmpty, let preferred = options.first(where: { $0.isDefault && $0.choice != nil }) {
            return .agent(preferred.id)
        }
        return items.first
    }

    private func move(by step: Int, in results: AgentPickerResults, from current: AgentPickerItem?) -> KeyPress.Result {
        let items = results.items
        guard !items.isEmpty else { return .handled }
        guard let index = current.flatMap(items.firstIndex(of:)) else {
            highlighted = step > 0 ? items.first : items.last
            return .handled
        }
        highlighted = items[(index + step + items.count) % items.count]
        return .handled
    }

    private func activate(_ item: AgentPickerItem, in results: AgentPickerResults) {
        switch item {
        case .addAgent:
            onAddAgent()
        case .agent(let id):
            if let option = results.agents.first(where: { $0.option.id == id })?.option, option.choice != nil {
                onChoose(option)
            }
        }
    }
}

extension AgentPickerPanel where Notice == EmptyView {
    init(
        options: [AgentPickerOption],
        projectName: String?,
        missingAgents: [String],
        defaultShortcut: String?,
        onChoose: @escaping (AgentPickerOption) -> Void,
        onRemedy: @escaping (AgentPickerOption) async -> Void,
        onAddAgent: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            options: options, projectName: projectName, missingAgents: missingAgents,
            defaultShortcut: defaultShortcut, onChoose: onChoose, onRemedy: onRemedy, onAddAgent: onAddAgent,
            onDismiss: onDismiss
        ) {
            EmptyView()
        }
    }
}
