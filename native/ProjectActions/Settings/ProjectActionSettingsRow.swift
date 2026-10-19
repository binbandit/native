import ProjectActions
import SwiftUI

/// One action in the project's settings: its icon, name, command, and where and how it runs.
struct ProjectActionSettingsRow<Controls: View>: View {
    let action: ProjectAction
    @ViewBuilder var controls: Controls

    var body: some View {
        SettingsRow(
            action.name,
            icon: action.icon ?? ProjectActionGlyph.fallback,
            description: Text(action.command).font(.dsMono),
            detail: Text(Self.whereItRuns(action))
        ) {
            HStack(spacing: DS.Space.sm) {
                controls
            }
        }
    }

    /// "Terminal tab · Task's worktree", "Background, with a toast · apps/web in the project's folder".
    static func whereItRuns(_ action: ProjectAction) -> String {
        let presentation = action.presentation == .terminal ? "Terminal tab" : "Background, with a toast"
        let base = action.directory.base == .worktree ? "task's worktree" : "project's folder"
        guard !action.directory.path.isEmpty else {
            return "\(presentation) · \(base.prefix(1).uppercased() + base.dropFirst())"
        }
        let folder = "\(action.directory.path) in the \(base)"
        return "\(presentation) · \(folder)"
    }
}

/// The "…" menu on one of the user's actions: move it up or down, or delete it.
struct ProjectActionRowMenu: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Menu {
            Button("Move Up") { move(-1) }
                .disabled(!canMoveUp)
            Button("Move Down") { move(1) }
                .disabled(!canMoveDown)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: SettingsMetrics.navGlyph, weight: .regular))
                .foregroundStyle(isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .background(isHovered ? Color.dsHover : .clear, in: shape)
                .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .trackHover($isHovered)
        .help("More for \(name)")
        .accessibilityLabel("More for \(name)")
        .accessibilityActions {
            if canMoveUp { Button("Move Up") { move(-1) } }
            if canMoveDown { Button("Move Down") { move(1) } }
            Button("Delete", action: delete)
        }
    }
}
