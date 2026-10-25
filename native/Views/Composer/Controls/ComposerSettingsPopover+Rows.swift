import SwiftUI

extension ComposerSettingsPopover {
    var taskRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                taskRow(row)
            }
            if let failed = failure, rows.contains(where: { $0.id == failed.optionID }) {
                ComposerSettingsCaption(
                    text: AttributedString(failed.message), isFailure: true,
                    action: failed.retry.map { ComposerSettingsTaskRow.Command(title: "Try Again", action: $0) })
            }
        }
    }

    @ViewBuilder private func taskRow(_ row: ComposerSettingsTaskRow) -> some View {
        let target = Target.row(row.id)
        let label = ComposerSettingsRow(highlight: highlight(of: target), isDimmed: isStopped) {
            Text(row.title)
        } trailing: {
            trailing(of: row)
        }
        Group {
            switch row.kind {
            case .menu(let choices, let commands):
                Menu {
                    ComposerSettingsMenuItems(choices: choices, commands: commands) { row.perform($0) }
                } label: {
                    label
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            case .page:
                Button {
                    row.perform(nil)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            case .toggle(let isOn):
                Button {
                    row.perform(isOn ? "off" : "on")
                } label: {
                    label
                }
                .buttonStyle(.plain)
            case .note:
                label
            }
        }
        .composerSettingsHover(target, hovered: $hovered)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.value + (row.failure.map { ", \($0)" } ?? ""))
        .accessibilityHint(row.accessibilityHint)
    }

    @ViewBuilder private func trailing(of row: ComposerSettingsTaskRow) -> some View {
        switch row.kind {
        case .menu:
            ComposerSettingsValue(
                text: row.value, failure: row.failure, isQuiet: row.isValueQuiet || isStopped,
                glyph: "chevron.up.chevron.down")
        case .page:
            ComposerSettingsValue(
                text: row.value, failure: row.failure, isQuiet: row.isValueQuiet || isStopped, glyph: "chevron.right")
        case .toggle(let isOn):
            Toggle(row.title, isOn: Binding(get: { isOn }, set: { row.perform($0 ? "on" : "off") }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(DS.isTouchPlatform ? .regular : .mini)
        case .note:
            ComposerSettingsValue(text: row.value, isQuiet: true)
        }
    }

    /// A menu row's choices as a page, so the keyboard and touch reach them like any other list.
    func choicesPage(_ row: ComposerSettingsTaskRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerSettingsPageHeader(title: row.title) { page = nil }
            if case .menu(let choices, let commands) = row.kind {
                ForEach(choices) { choice in
                    let target = Target.row("\(row.id)/\(choice.id)")
                    Button {
                        row.perform(choice.id)
                        page = nil
                    } label: {
                        ComposerSettingsRow(mark: choice.isCurrent ? .check : .none, highlight: highlight(of: target)) {
                            Text(choice.name)
                        } trailing: {
                            if let section = choice.section {
                                Text(section).font(DS.ComposerSettings.detailFont).foregroundStyle(.dsTextTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .composerSettingsHover(target, hovered: $hovered)
                    .accessibilityAddTraits(choice.isCurrent ? .isSelected : [])
                }
                let previewed = choices.first { highlight(of: .row("\(row.id)/\($0.id)")) != .none }
                let summaries = choices.compactMap(\.summary)
                if !summaries.isEmpty {
                    ComposerSettingsCaption(
                        text: (previewed ?? choices.first(where: \.isCurrent))?.summary.map { AttributedString($0) },
                        reserving: summaries.map { AttributedString($0) })
                }
                if !commands.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commands) { command in
                            Button(action: command.action) {
                                ComposerSettingsRow { Text(command.title) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .composerSettingsSection(ruled: true)
                    .padding(.top, DS.Space.md)
                }
            }
        }
        .padding(.bottom, DS.ComposerSettings.sectionInset)
    }

    /// Choice targets on a menu row's page, in order.
    func pageTargets(_ row: ComposerSettingsTaskRow) -> [Target] {
        guard case .menu(let choices, _) = row.kind else { return [] }
        return choices.map { .row("\(row.id)/\($0.id)") }
    }
}

/// A value row's trailing side: the value, a failure in red, and the glyph that says what it opens.
struct ComposerSettingsValue: View {
    let text: String
    var failure: String?
    var isQuiet = false
    var glyph: String?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(
                "\(Text(text).foregroundStyle(isQuiet ? .dsTextTertiary : .dsTextSecondary))\(Text(failure.map { " · \($0)" } ?? "").foregroundStyle(.dsDanger))"
            )
            .font(DS.ComposerSettings.rowFont)
            .lineLimit(1)
            .truncationMode(.tail)
            if let glyph {
                Image(systemName: glyph)
                    .font(DS.ComposerSettings.glyphFont)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Space.lg)
            }
        }
    }
}

/// A menu row's choices as a native menu, grouped by section and checked, then its commands.
struct ComposerSettingsMenuItems: View {
    let choices: [ComposerSettingsTaskRow.Choice]
    let commands: [ComposerSettingsTaskRow.Command]
    let choose: (String) -> Void

    var body: some View {
        let sections = choices.reduce(into: [String?]()) { if !$0.contains($1.section) { $0.append($1.section) } }
        ForEach(sections, id: \.self) { section in
            let items = choices.filter { $0.section == section }
            if let section {
                Section(section) { ForEach(items, content: item) }
            } else {
                ForEach(items, content: item)
            }
        }
        if !commands.isEmpty {
            Divider()
            ForEach(commands) { command in
                Button(command.title, action: command.action)
            }
        }
    }

    private func item(_ choice: ComposerSettingsTaskRow.Choice) -> some View {
        Toggle(isOn: Binding(get: { choice.isCurrent }, set: { _ in choose(choice.id) })) {
            Text(choice.name)
            if let summary = choice.summary { Text(summary) }
        }
    }
}
