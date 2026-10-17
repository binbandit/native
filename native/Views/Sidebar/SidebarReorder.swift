import SwiftUI

/// Moves the sidebar's selected item one place up or down, for ⌥⌘↑ / ⌥⌘↓ (docs/keyboard.md): the
/// selected session within its project or, with no session selected, the project whose home is
/// showing. The sidebar publishes it as a scene focused value, so the Session menu can drive it
/// while the composer has focus.
struct SidebarReorder {
    enum Direction {
        case up, down
    }

    let canMove: (Direction) -> Bool
    let move: (Direction) -> Void
}

extension FocusedValues {
    /// The main window's sidebar reordering, for the Session menu's Move Up and Move Down.
    @Entry var sidebarReorder: SidebarReorder?
    /// Whether the sidebar shows only the tasks that need the user, for the View menu (⌥⌘J).
    @Entry var sidebarNeedsYouFilter: Binding<Bool>?
}

/// What a keyboard move applies to.
enum SidebarMoveTarget: Equatable {
    case project(Project.ID)
    case session(SessionKey, in: Project.ID)
}

extension AppModel {
    /// The item ⌥⌘↑ / ⌥⌘↓ moves: the selected session, or with none selected, the project whose
    /// home is showing.
    var sidebarMoveTarget: SidebarMoveTarget? {
        if let selection {
            return sessionList.first { $0.id == selection }.map { .session($0.id, in: $0.project) }
        }
        return currentProject.map { .project($0.id) }
    }

    func canMove(_ target: SidebarMoveTarget, _ direction: SidebarReorder.Direction) -> Bool {
        guard let (index, count) = position(of: target) else { return false }
        return direction == .up ? index > 0 : index < count - 1
    }

    /// Moves a project among projects, or a session among its project's sessions, by one place.
    func move(_ target: SidebarMoveTarget, _ direction: SidebarReorder.Direction) {
        guard canMove(target, direction), let (index, _) = position(of: target) else { return }
        // `move(fromOffsets:toOffset:)` counts the destination before removal, so one place down is +2.
        let destination = direction == .up ? index - 1 : index + 2
        switch target {
        case .project:
            moveProjects(fromOffsets: [index], toOffset: destination)
        case .session(_, let project):
            moveSessions(in: project, fromOffsets: [index], toOffset: destination)
        }
    }

    private func position(of target: SidebarMoveTarget) -> (index: Int, count: Int)? {
        switch target {
        case .project(let id):
            let ids = projects.all.map(\.id)
            return ids.firstIndex(of: id).map { ($0, ids.count) }
        case .session(let key, let project):
            let keys = sessions(in: project).map(\.id)
            return keys.firstIndex(of: key).map { ($0, keys.count) }
        }
    }
}
