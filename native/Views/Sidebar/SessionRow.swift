import ACP
import SwiftUI

/// A session in the sidebar (the reference app's workspace row): the agent's icon or the session's status,
/// its title and age, and `accessory` (pull request, branch state and context usage, as the app
/// wires it) at the trailing edge. One line always; what a waiting session asks goes in its tooltip
/// and VoiceOver label. Every action is in the context menu, hover shows Archive, and on touch the
/// row swipes. Double-click, Return or the menu renames it in place.
struct SessionRow<Accessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let summary: SessionSummary
    /// Grouped under a project header, or flush in the Pinned section.
    var indent: TaskRowIndent = .grouped
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

    private var isPinned: Bool {
        model.isPinned(summary.id)
    }

    var body: some View {
        if model.renaming == summary.id {
            SessionTitleField(summary: summary, status: TaskStatus(session))
        } else {
            TaskRow(
                title: title,
                status: TaskStatus(session),
                isSelected: model.selection == summary.id,
                isUnread: isUnread,
                date: session?.lastActivity ?? summary.info.updatedDate,
                badge: badge,
                indent: indent,
                leading: AgentIcon(agent: summary.agent),
                accessory: accessory,
                action: select,
                onArchive: archive
            )
            .help(tooltip)
            // Double-clicking renames, like a file in the Finder.
            .simultaneousGesture(TapGesture(count: 2).onEnded(rename))
            .contextMenu { menu }
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

    @ViewBuilder private var menu: some View {
        Button("Rename…", action: rename)
        Button(isUnread ? "Mark as Read" : "Mark as Unread", action: toggleUnread)
        Button(isPinned ? "Unpin" : "Pin", action: togglePinned)
        Divider()
        Button("Move Up") { model.move(target, .up) }
            .disabled(!model.canMove(target, .up))
        Button("Move Down") { model.move(target, .down) }
            .disabled(!model.canMove(target, .down))
        Divider()
        Button("Copy Session ID") {
            DSPasteboard.copy(summary.info.sessionId.rawValue)
        }
        Divider()
        Button("Archive", action: archive)
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
        let line = "\(summary.agent.displayName) · \(title)\(project ?? "")"
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
    /// What the session is waiting on the user for, in a few words: "Allow Run `rm -rf build`?", or
    /// nil when it isn't waiting.
    var sidebarAsk: String? {
        let pending = state.pendingPermissions
        if let first = pending.first {
            let title = state.items.lazy.compactMap { item -> String? in
                if case .toolCall(let call) = item, call.id == first.toolCallID { call.title } else { nil }
            }.first
            let ask = "Allow \(title ?? "a tool call")?"
            return pending.count > 1 ? "\(ask) (\(pending.count - 1) more)" : ask
        }
        return needsApproval ? "A subagent is waiting for approval" : nil
    }
}

/// The trailing indicator task rows show until the Usage feature supplies its own: the reference app's
/// context ring, once a session has used most of its context window.
struct SessionContextUsage: View {
    @Environment(AppModel.self) private var model
    let summary: SessionSummary

    /// the reference app shows the ring past 70%.
    private static let threshold = 0.7

    var body: some View {
        if let fraction = model.session(summary.id)?.state.usage?.fractionUsed, fraction >= Self.threshold {
            ContextUsageRing(fraction: fraction)
        }
    }
}
