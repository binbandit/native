import Observation
import SwiftUI
import TaskList

/// The window's multi-selection in the sidebar, for bulk actions: ⌘-click and ⇧-click pick tasks,
/// ⌘A picks a project's, and on touch a select mode makes taps pick. The task open in the detail
/// column is the model's `selection`, apart from this.
@Observable
final class SidebarSelectionModel {
    private(set) var picked = TaskListSelection<SessionKey>()
    /// Taps pick tasks instead of opening them (Select, on touch or from the menu).
    var isSelecting = false {
        didSet {
            if !isSelecting { picked.clear() }
        }
    }
    /// The keys held down, kept up to date by the sidebar.
    @ObservationIgnored var modifiers: EventModifiers = []
    /// The tasks on screen, top to bottom, kept up to date by the sidebar.
    @ObservationIgnored var order: [SessionKey] = []
    /// Asks the sidebar to confirm deleting the picked tasks.
    var isConfirmingDelete = false
    /// Asks the sidebar to confirm deleting one task. One dialog for the whole list, rather than
    /// one per row, keeps rows cheap to build.
    var deletionRequest: SessionKey?

    /// Whether the selection bar shows: in select mode, or with more than one task picked.
    var isActive: Bool {
        isSelecting || picked.count > 1
    }

    func contains(_ key: SessionKey) -> Bool {
        isActive && picked.contains(key)
    }

    /// The picked tasks in the sidebar's order, while the selection is active.
    var keys: [SessionKey] {
        isActive ? picked.ordered(by: order) : []
    }

    /// A row was clicked. Returns whether it picked rather than opened: with ⌘ or ⇧ held, or in
    /// select mode. A plain click lets the picks go.
    func handleClick(on key: SessionKey, current: SessionKey?) -> Bool {
        if modifiers.contains(.shift) {
            picked.extend(to: key, in: order, current: current)
        } else if modifiers.contains(.command) || isSelecting {
            picked.toggle(key, current: isSelecting ? nil : current)
        } else {
            picked.clear()
            return false
        }
        return true
    }

    func selectAll(_ keys: [SessionKey]) {
        picked.selectAll(keys)
    }

    func clear() {
        isSelecting = false
        picked.clear()
    }

    /// Follows the list on screen, letting go of tasks no longer on it.
    func update(order: [SessionKey]) {
        self.order = order
        guard !picked.isEmpty else { return }
        let existing = Set(order)
        if !picked.ids.isSubset(of: existing) {
            picked.keep(only: existing)
        }
    }
}

extension FocusedValues {
    /// The focused window's sidebar multi-selection, for the bulk commands.
    @Entry var sidebarSelection: SidebarSelectionModel?
}

extension EnvironmentValues {
    @Entry var sidebarSelection: SidebarSelectionModel?
}
