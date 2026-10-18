import Foundation
import NativeCommands

extension CommandPaletteSource {
    /// The registry's commands that can run now, with their current shortcuts.
    static func commands(_ registry: CommandRegistry) -> Self {
        Self { _, context in
            registry.commands
                .filter { $0.showsInPalette && $0.id != .paletteShow && $0.isAvailable(context) }
                .map { command in
                    CommandPaletteItem(
                        id: .init("command:\(command.id)"),
                        kind: .command,
                        title: command.menuTitle?(context) ?? command.title,
                        subtitle: command.category.title,
                        systemImage: command.systemImage ?? "command",
                        shortcut: registry.shortcut(for: command.id),
                        keywords: [command.title] + command.keywords,
                        isOn: command.isOn?(context)
                    ) {
                        command.perform(context)
                    }
                }
        }
    }

    /// Commands that take the typed text, such as searching transcripts for it.
    static func queryCommands(_ registry: CommandRegistry) -> Self {
        Self { query, context in
            let text = query.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return [] }
            return registry.commands.compactMap { command in
                guard let perform = command.performWithQuery, command.isAvailable(context) else { return nil }
                return CommandPaletteItem(
                    id: .init("query:\(command.id)"),
                    kind: .query,
                    title: "\(command.title) for \u{201C}\(text)\u{201D}",
                    systemImage: command.systemImage ?? "magnifyingglass",
                    shortcut: registry.shortcut(for: command.id)
                ) {
                    perform(text, context)
                }
            }
        }
    }

    /// The sidebar's tasks, in its order.
    static func tasks(model: AppModel, settings: SettingsPresentation) -> Self {
        Self { _, _ in
            model.sessionList.map { summary in
                CommandPaletteItem(
                    id: .init("task:\(summary.id.agent.rawValue)/\(summary.id.id)"),
                    kind: .task,
                    title: model.title(for: summary),
                    subtitle: model.projects.project(summary.project)?.name,
                    systemImage: "bubble.left",
                    keywords: [summary.agent.displayName]
                ) {
                    settings.close()
                    model.selection = summary.id
                }
            }
        }
    }

    /// The open projects; choosing one shows its home, where new sessions go to it.
    static func projects(model: AppModel, settings: SettingsPresentation) -> Self {
        Self { _, _ in
            model.projects.all.map { project in
                CommandPaletteItem(
                    id: .init("project:\(project.id)"),
                    kind: .project,
                    title: project.name,
                    subtitle: project.path,
                    systemImage: "folder"
                ) {
                    settings.close()
                    model.focusProject(project.id)
                }
            }
        }
    }

    /// Settings' pages, each its own feature's included.
    static func settingsPages(
        _ panes: @escaping @MainActor () -> [SettingsPane], settings: SettingsPresentation
    )
        -> Self
    {
        Self { _, _ in
            panes().map { pane in
                CommandPaletteItem(
                    id: .init("settings:\(pane.id.rawValue)"),
                    kind: .settings,
                    title: pane.title,
                    subtitle: "Settings",
                    systemImage: pane.systemImage,
                    keywords: pane.keywords + ["settings", "preferences"]
                ) {
                    settings.open(pane.id)
                }
            }
        }
    }
}
