import ACP
import MCPClient
import Modes
import NativeAutomation
import SwiftUI

extension ComposerSettingsControl {
    /// Mode, Goal, MCP servers, then the agent's own settings, Web search first.
    func taskRows(openGoal: @escaping () -> Void, openMCP: @escaping () -> Void) -> [ComposerSettingsTaskRow] {
        var rows = [modeRow]
        if let controller = automation.goal(for: session) {
            let objective = controller.goal?.objective
            rows.append(
                ComposerSettingsTaskRow(
                    id: "goal", title: "Goal", value: objective.map(Self.firstWords) ?? "None",
                    isValueQuiet: objective == nil, kind: .page
                ) { _ in openGoal() })
        }
        rows.append(mcpRow(open: openMCP))
        let agentSettings = Array(settings.modelSwitches.dropFirst()) + settings.others
        let webSearch = agentSettings.filter { Self.isWebSearch($0.option) }
        rows += (webSearch + agentSettings.filter { !Self.isWebSearch($0.option) }).map(row(for:))
        return rows
    }

    private var modeRow: ComposerSettingsTaskRow {
        let catalog = mode.catalog
        let current = mode.current.id
        func choices(_ modes: [Mode], section: String?) -> [ComposerSettingsTaskRow.Choice] {
            modes.map {
                .init(
                    id: $0.id.rawValue, name: $0.name, summary: $0.summary, section: section,
                    isCurrent: $0.id == current)
            }
        }
        let all =
            choices(catalog.builtIn, section: nil) + choices(catalog.custom, section: "Your modes")
            + choices(catalog.project, section: mode.projectName.map { "From \($0)" } ?? "From the project")
        let commands = presentation.map { presentation in
            [ComposerSettingsTaskRow.Command(title: "Edit Modes…") { presentation.open(.modes) }]
        }
        return ComposerSettingsTaskRow(
            id: "mode", title: "Mode", value: mode.current.name, kind: .menu(all, commands: commands ?? [])
        ) { id in
            if let id { mode.select(Mode.ID(rawValue: id)) }
        }
    }

    private func mcpRow(open: @escaping () -> Void) -> ComposerSettingsTaskRow {
        guard let library else {
            return ComposerSettingsTaskRow(id: "mcp", title: "MCP servers", value: "Extension is off", kind: .note) {
                _ in
            }
        }
        let active = library.entries(forSession: session.clientID).filter(\.isActive)
        let failed = active.count { entry in
            switch library.health(of: entry.key) {
            case .failed: true
            default: false
            }
        }
        return ComposerSettingsTaskRow(
            id: "mcp", title: "MCP servers", value: "\(active.count)", isValueQuiet: active.isEmpty,
            failure: failed > 0 ? "\(failed) failed" : nil, kind: .page
        ) { _ in open() }
    }

    /// One of the agent's own settings: a switch for on and off, else a menu of its choices.
    private func row(for setting: SelectSetting) -> ComposerSettingsTaskRow {
        let option = setting.option
        let kind: ComposerSettingsTaskRow.Kind =
            setting.isSwitch
            ? .toggle(isOn: setting.isOn)
            : .menu(
                setting.choices.map {
                    .init(
                        id: $0.value, name: $0.name, summary: $0.descriptionWithoutName,
                        isCurrent: $0.value == setting.value)
                }, commands: [])
        return ComposerSettingsTaskRow(id: option.id, title: option.name, value: setting.currentName, kind: kind) {
            value in
            if let value, value != setting.value { set(setting, value) }
        }
    }

    /// ACP has no web search category; agents name it.
    private static func isWebSearch(_ option: ConfigOption) -> Bool {
        option.category == "web_search" || option.name.localizedCaseInsensitiveCompare("Web search") == .orderedSame
    }

    /// The goal's opening words, for its row.
    static func firstWords(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.prefix(6).joined(separator: " ") + (words.count > 6 ? "…" : "")
    }
}
