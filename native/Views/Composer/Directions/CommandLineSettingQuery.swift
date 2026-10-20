#if DEBUG
import ACP
import Foundation
import Modes

/// One value a typed setting command can take, as direction B lists it under the draft.
struct CommandLineChoice: Identifiable, Equatable {
    enum Action: Equatable {
        case setting(SelectSetting, String)
        case mode(Mode.ID)
    }

    let id: String
    let name: String
    let detail: String?
    let isCurrent: Bool
    let action: Action
}

/// A setting set by typing, direction B's way: `/model sol`, `/effort high`, `/autonomy auto`,
/// `/mode plan`. The draft is the command and what's typed after it narrows the values.
struct CommandLineSettingQuery: Equatable {
    enum Command: String, CaseIterable {
        case model, effort, autonomy, mode
    }

    let command: Command
    let filter: String

    init?(draft: String) {
        guard draft.hasPrefix("/"), !draft.contains("\n") else { return nil }
        let body = draft.dropFirst()
        guard let space = body.firstIndex(of: " "),
            let command = Command(rawValue: body[..<space].lowercased())
        else { return nil }
        self.command = command
        filter = body[body.index(after: space)...].trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The values matching what's typed, in the agent's order.
    func choices(settings: ComposerSettings, mode: TaskModeControl, resumedAutonomy: String?) -> [CommandLineChoice] {
        let all = Self.all(command, settings: settings, mode: mode, resumedAutonomy: resumedAutonomy)
        guard !filter.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(filter) }
    }

    static func all(
        _ command: Command, settings: ComposerSettings, mode: TaskModeControl, resumedAutonomy: String?
    )
        -> [CommandLineChoice]
    {
        switch command {
        case .model:
            return settings.model.map(values(of:)) ?? []
        case .effort:
            return settings.effort.map(values(of:)) ?? []
        case .autonomy:
            guard let autonomy = settings.autonomy else { return [] }
            let levels = settings.autonomyLevels
            let index = settings.shownAutonomyLevel(resumed: resumedAutonomy)
            let shown = levels.indices.contains(index) ? levels[index] : nil
            return levels.map { choice in
                CommandLineChoice(
                    id: choice.value, name: choice.name, detail: AutonomySummary.summary(of: choice),
                    isCurrent: choice.value == shown?.value, action: .setting(autonomy, choice.value))
            }
        case .mode:
            let current = mode.current.id
            return mode.catalog.all.map { candidate in
                CommandLineChoice(
                    id: candidate.id.rawValue, name: candidate.name, detail: candidate.summary,
                    isCurrent: candidate.id == current, action: .mode(candidate.id))
            }
        }
    }

    private static func values(of setting: SelectSetting) -> [CommandLineChoice] {
        setting.choices.map { choice in
            CommandLineChoice(
                id: choice.value, name: choice.name, detail: choice.description,
                isCurrent: choice.value == setting.value,
                action: .setting(setting, choice.value))
        }
    }

    /// The setting commands for the `/` list, each described by its current value.
    static func commands(
        settings: ComposerSettings, mode: TaskModeControl, resumedAutonomy: String?
    )
        -> [ComposerSlashCommand]
    {
        Command.allCases.compactMap { command in
            let current = all(command, settings: settings, mode: mode, resumedAutonomy: resumedAutonomy)
                .first(where: \.isCurrent)
            return current.map { ComposerSlashCommand(native: command.rawValue, description: $0.name) }
        }
    }
}
#endif
