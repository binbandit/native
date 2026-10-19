import ACP
import SwiftUI

/// A session in the sidebar: the agent's icon or the session's status,
/// its title and age, and `accessory` (pull request, branch state and context usage, as the app
/// wires it) at the trailing edge. One line always; what a waiting session asks goes in its tooltip
/// and VoiceOver label. Every action is in the context menu, hover shows Archive, and on touch the
/// row swipes. Double-click, Return or the menu renames it in place.
struct SessionRow<Accessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.sidebarSelection) private var picking
    let summary: SessionSummary
    /// Grouped under a project header, or flush in the Pinned section.
    var indent: TaskRowIndent = .grouped
    /// Whether the row is in the Pinned section.
    var isPinned = false
    /// Where the row can move, worked out once by its list: the context menu is built on every
    /// update of any session, so it must not query the model's ordering itself.
    let canMoveUp: Bool
    let canMoveDown: Bool
    let accessory: Accessory
    let select: () -> Void

    @State private var isConfirmingDelete = false

    private var session: SessionModel? {
        model.session(summary.id)
    }

    private var title: String {
        model.title(for: summary)
    }

    private var isUnread: Bool {
        model.isUnread(summary.id)
    }

    /// Shown only while the filter includes archived tasks.
    private var isArchived: Bool {
        model.isArchived(summary.id)
    }

    /// Open in the detail column, or picked for a bulk action.
    private var isSelected: Bool {
        model.selection == summary.id || picking?.contains(summary.id) == true
    }

    /// Hover's Archive button; an archived task (shown while the filter includes them) has none.
    private var archiveAction: (() -> Void)? {
        isArchived ? nil : { archive() }
    }

    /// Picked along with other tasks, so its context menu acts on all of them.
    private var isPickedWithOthers: Bool {
        guard let picking, picking.contains(summary.id) else { return false }
        return picking.keys.count > 1
    }

    var body: some View {
        if model.renaming == summary.id {
            SessionTitleField(summary: summary, status: TaskStatus(session))
        } else {
            TaskRow(
                title: title,
                status: TaskStatus(session),
                isSelected: isSelected,
                isUnread: isUnread,
                date: session?.lastActivity ?? summary.info.updatedDate,
                badge: badge,
                indent: indent,
                leading: AgentIcon(agent: summary.agent),
                accessory: accessory,
                action: select,
                onArchive: archiveAction
            )
            .help(tooltip)
            // Double-clicking renames, like a file in the Finder.
            .simultaneousGesture(TapGesture(count: 2).onEnded(rename))
            .contextMenu { contextMenu }
            .sidebarSwipeActions(
                leading: [readAction, pinAction],
                trailing: [
                    SidebarSwipeAction("Archive", systemImage: "archivebox", tint: .dsInfo, action: archive),
                    SidebarSwipeAction("Delete", systemImage: "trash", tint: .dsDanger) { isConfirmingDelete = true },
                ]
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("\(summary.agent.displayName) session. Return renames it.")
            .accessibilityActions {
                Button("Rename", action: rename)
                Button(isUnread ? "Mark as Read" : "Mark as Unread", action: toggleUnread)
                Button(isPinned ? "Unpin" : "Pin", action: togglePinned)
                Button("Archive", action: archive)
                Button("Move Up") { model.move(target, .up) }
                Button("Move Down") { model.move(target, .down) }
            }
            .confirmationDialog("Delete “\(title)”?", isPresented: $isConfirmingDelete) {
                Button("Delete Task", role: .destructive) {
                    model.deleteSession(summary.id, undoManager: undoManager)
                }
            } message: {
                Text(
                    "Its history goes from Native and, if \(summary.agent.displayName) supports it, from \(summary.agent.displayName) too. You can undo for a few seconds. To keep it out of sight instead, archive it."
                )
            }
        }
    }

    /// A row picked with others acts on all of them; otherwise on itself.
    @ViewBuilder private var contextMenu: some View {
        if let picking, isPickedWithOthers {
            SidebarBulkMenu(selection: picking)
        } else {
            menu
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Rename…", action: rename)
        Button(isUnread ? "Mark as Read" : "Mark as Unread", action: toggleUnread)
        Button(isPinned ? "Unpin" : "Pin", action: togglePinned)
        Divider()
        Button("Move Up") { model.move(target, .up) }
            .disabled(!canMoveUp)
        Button("Move Down") { model.move(target, .down) }
            .disabled(!canMoveDown)
        Divider()
        Button("Copy Session ID") {
            DSPasteboard.copy(summary.info.sessionId.rawValue)
        }
        Divider()
        if isArchived {
            Button("Unarchive") { Task { await model.unarchiveSession(summary.id) } }
        } else {
            Button("Archive", action: archive)
        }
        Button("Delete…", role: .destructive) { isConfirmingDelete = true }
    }

    private var readAction: SidebarSwipeAction {
        SidebarSwipeAction(
            isUnread ? "Read" : "Unread",
            systemImage: isUnread ? "envelope.open" : "envelope.badge",
            tint: .dsAccent,
            action: toggleUnread
        )
    }

    private var pinAction: SidebarSwipeAction {
        SidebarSwipeAction(
            isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin", tint: .dsWarning,
            action: togglePinned)
    }

    private var target: SidebarMoveTarget {
        isPinned ? .pinned(summary.id) : .session(summary.id, in: summary.project)
    }

    /// Queued follow-ups, counted at the trailing edge.
    private var badge: TaskBadge? {
        guard let count = session?.queuedPrompts.count, count > 0 else { return nil }
        return .count(count)
    }

    /// The agent and title (and project, when pinned away from it), then what the session is
    /// waiting on, so triage needs no click.
    private var tooltip: String {
        let project = indent == .flat ? model.projects.project(summary.project).map { " · \($0.name)" } : nil
        let line = "\(summary.agent.displayName) · \(title)\(project ?? "")\(isArchived ? " · Archived" : "")"
        return [line, session?.sidebarAsk].compactMap(\.self).joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        [title, session?.sidebarAsk].compactMap(\.self).joined(separator: ", ")
    }

    private func rename() {
        model.renaming = summary.id
    }

    private func toggleUnread() {
        model.setUnread(summary.id, !isUnread)
    }

    private func togglePinned() {
        model.setPinned(summary.id, !isPinned, undoManager: undoManager)
    }

    private func archive() {
        Task { await model.archiveSession(summary.id, undoManager: undoManager) }
    }
}

extension TaskStatus {
    /// How the sidebar shows a session. One that hasn't been opened in this run is idle.
    init(_ session: SessionModel?) {
        guard let session else {
            self = .idle
            return
        }
        if session.needsApproval {
            self = .needsPermission
            return
        }
        self =
            switch session.phase {
            case .loading: .starting
            case .prompting: .working
            case .disconnected: .failed
            case .idle: .idle
            }
    }
}

extension SessionModel {
    /// What the session (or a subagent under it) is waiting on the user for, in a line: "Allow Run
    /// `rm -rf build`?", "Waiting for your answer: …", or nil when it isn't waiting.
    var sidebarAsk: String? {
        guard let wait else { return nil }
        let more = permissionRequests.count - 1
        if case .permission = wait, more > 0 {
            return "\(wait.summary) (\(more) more)"
        }
        return wait.summary
    }
}

/// The trailing indicator task rows show until the Usage feature supplies its own: the
/// context ring, once a session has used most of its context window.
struct SessionContextUsage: View {
    @Environment(AppModel.self) private var model
    let summary: SessionSummary

    /// Below this the ring would be noise: there's plenty of room left.
    private static let threshold = 0.7

    var body: some View {
        if let fraction = model.session(summary.id)?.usage?.fractionUsed, fraction >= Self.threshold {
            ContextUsageRing(fraction: fraction)
        }
    }
}
