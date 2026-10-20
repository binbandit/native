import NativeCommands
import SessionTools
import SwiftUI

extension FocusedValues {
    /// The focused window's session tools, published by `SessionToolsScreen` for the tool commands.
    @Entry var sessionTools: SessionToolsScreenModel?
}

extension CommandID {
    static let sessionToolChanges: Self = "sessionTools.changes"
    static let sessionToolSubagents: Self = "sessionTools.subagents"
    static let sessionToolPullRequest: Self = "sessionTools.pullRequest"
}

extension NativeCommand {
    /// View ▸ Tools: one key per tool (⌥⌘1–⌥⌘5, `docs/keyboard.md`), which shows or hides it
    /// wherever it lives. Listed while the window's task has the tool on.
    static let sessionTools: [NativeCommand] = [
        sessionTool(.changes, command: .sessionToolChanges, title: "Changes", systemImage: "plus.forwardslash.minus"),
        sessionTool(.subagents, command: .sessionToolSubagents, title: "Subagents", systemImage: "person.2"),
        sessionTool(
            .pullRequest, command: .sessionToolPullRequest, title: "Pull Request", systemImage: "arrow.triangle.pull"),
    ]

    private static func sessionTool(
        _ tool: SessionToolID, command: CommandID, title: String, systemImage: String
    ) -> NativeCommand {
        NativeCommand(command, title: "Show or Hide \(title)", category: .view, systemImage: systemImage) {
            $0.sessionTools?.toggle(tool)
        }
        .menuTitle { $0.sessionTools?.isOpen(tool) == true ? "Hide \(title)" : "Show \(title)" }
        .available { $0.sessionTools.map { $0.registry.place(of: tool) != .off } ?? false }
    }
}
