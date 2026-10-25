import ACP
import SwiftUI
import TaskList

/// A session in the sidebar: the agent's icon or the session's status,
/// its title and age, and `accessory` (pull request, branch state and context usage, as the app
/// wires it) at the trailing edge. One line always; what a waiting session asks goes in its tooltip
/// and VoiceOver label. Every action is in the context menu (with a "Pull Request" submenu when its
/// branch has one), hover shows Archive in place of the age, and on touch the row swipes.
/// Double-click, Return or the menu renames it in place.
struct SessionRow<Accessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.sidebarSelection) private var picking
    @Environment(\.sidebarTaskInsights) private var insights
    @AppStorage("sidebar.showAgentIcons") private var showAgentIcons = true
    @Environment(\.sidebarAllInView) private var isAllInView
    @Environment(\.homePresentedTaskNeeds) private var homeNeeds
    @Environment(\.oldestTaskAskID) private var oldestAskID
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
        row.environment(\.dsWorkingAnimation, session?.workingAnimation)
    }

    @ViewBuilder private var row: some View {
        if model.renaming == summary.id {
            SessionTitleField(summary: summary, status: TaskStatus(session))
        } else {
            taskRow
                .taskPeekAnchor(summary.id)
                .onTaskForceClick(enabled: isAllInView) { model.peekTask(summary.id) }
                .help(tooltip)
                // Double-clicking renames, like a file in the Finder.
                .simultaneousGesture(TapGesture(count: 2).onEnded(rename))
                .contextMenu { contextMenu }
                .sidebarSwipeActions(
                    leading: [readAction, pinAction],
                    trailing: [
                        SidebarSwipeAction("Archive", systemImage: "archivebox", tint: .dsInfo, action: archive),
                        SidebarSwipeAction("Delete", systemImage: "trash", tint: .dsDanger, action: requestDeletion),
                    ]
                )
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("\(summary.agent.displayName) task. Return renames it.")
                .accessibilityActions {
                    if isAllInView { Button("Peek") { model.peekTask(summary.id) } }
                    Button("Rename", action: rename)
                    Button(isUnread ? "Mark as Read" : "Mark as Unread", action: toggleUnread)
                    Button(isPinned ? "Unpin" : "Pin", action: togglePinned)
                    Button("Archive", action: archive)
                    Button("Move Up") { model.move(target, .up) }
                    Button("Move Down") { model.move(target, .down) }
                    if let pullRequest = insights.pullRequestMenu(summary) {
                        ForEach(pullRequest.items) { item in
                            Button(item.spokenTitle, action: item.perform)
                        }
                    }
                }
        }
    }

    @ViewBuilder private var taskRow: some View {
        if isAllInView {
            let attention = session.flatMap {
                SidebarSessionAttention(session: $0, task: summary.id, oldest: oldestAskID)
            }
            let preferences = model.sidebarPreferences
            let isOnHome =
                attention.map { homeNeeds.contains(.request($0.id)) }
                ?? homeNeeds.contains(.failure(summary.id))
            let hidesAsk = isOnHome || !preferences.shows(.needs)
            AllInViewTaskRow(
                title: title, status: TaskStatus(session), isSelected: isSelected,
                isPeeking: model.taskPeek.request?.task == summary.id, isUnread: isUnread,
                ask: hidesAsk ? nil : attention?.sentence ?? recoverySentence, attentionSince: attention?.since,
                showsAttentionClock: !isOnHome,
                answersShortcut: !hidesAsk && attention?.answersShortcut == true,
                askShortcut: CommandRegistry.shared.keyboardShortcut(for: .taskAnswerOldestAsk),
                unavailable: unavailableSentence,
                hostName: preferences.shows(.machines) ? remoteHost?.name : nil,
                date: preferences.shows(.ages) ? model.lastActivity(for: summary) : nil,
                changes: preferences.shows(.changes) ? finishedChanges : nil,
                agentName: preferences.shows(.agents) ? summary.agent.displayName : nil,
                branchName: preferences.shows(.branches) ? insights.branch(summary) : nil,
                peek: { model.peekTask(summary.id) },
                action: { if model.taskPeek.request?.task != summary.id { select() } }
            )
            .task(id: preferences.shows(.branches)) {
                if preferences.shows(.branches) { await insights.prepareBranch(summary) }
            }
        } else {
            TaskRow(
                title: title, status: TaskStatus(session), isSelected: isSelected, isUnread: isUnread,
                date: model.lastActivity(for: summary), badge: badge, indent: indent,
                leading: AgentIcon(agent: summary.agent).opacity(showAgentIcons ? 1 : 0), accessory: accessory,
                action: select, onArchive: archiveAction)
        }
    }

    private var finishedChanges: (added: Int, removed: Int)? {
        guard let session, session.taskStatus == .done, let turn = session.state.turns.last else { return nil }
        let summary = session.state.summary(of: turn)
        return (summary.linesAdded, summary.linesRemoved)
    }

    private var remoteHost: RemoteHost? {
        guard case .remote(let id) = model.device(of: summary.id) else { return nil }
        return model.hosts.host(id)
    }

    private var unavailableSentence: String? {
        guard let host = remoteHost, !host.isOnline else { return nil }
        if let lastConnected = host.lastConnected {
            return
                "\(host.name) is offline. Last connected \(lastConnected.formatted(date: .omitted, time: .shortened))."
        }
        return "\(host.name) is offline. Reconnect to continue."
    }

    private var recoverySentence: String? {
        if let removed = model.removedWorkspaces[summary.id] { return "Its worktree was removed. \(removed.detail)" }
        if TaskStatus(session) == .failed { return "The task stopped unexpectedly. Open it to retry or switch models." }
        return nil
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
        if isAllInView {
            Button("Peek") { model.peekTask(summary.id) }
            Divider()
        }
        if model.offersAgentChange, let session {
            Button("Change Agent…") { model.requestAgentChange(session) }
        }
        Button("Rename…", action: rename)
        Button(isUnread ? "Mark as Read" : "Mark as Unread", action: toggleUnread)
        Button(isPinned ? "Unpin" : "Pin", action: togglePinned)
        if let pullRequest = insights.pullRequestMenu(summary) {
            Divider()
            Menu(pullRequest.title) {
                ForEach(pullRequest.items) { item in
                    Button(item.title, action: item.perform)
                }
            }
        }
        Divider()
        Button("Move Up") { model.move(target, .up) }
            .disabled(!canMoveUp)
        Button("Move Down") { model.move(target, .down) }
            .disabled(!canMoveDown)
        Divider()
        Button("Copy Task ID") {
            DSPasteboard.copy(summary.info.sessionId.rawValue)
        }
        Divider()
        if isArchived {
            Button("Unarchive") { Task { await model.unarchiveSession(summary.id) } }
        } else {
            Button("Archive", action: archive)
        }
        Button("Delete…", role: .destructive, action: requestDeletion)
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

    /// At the trailing edge: what a task whose worktree was removed outside Native wants done, else
    /// its queued follow-ups, counted.
    private var badge: TaskBadge? {
        // What to do about it, like "Approve"; the tooltip and VoiceOver say what happened.
        if let removed = model.removedWorkspaces[summary.id] {
            return .attention(removed.branch == nil ? "Archive" : "Restore")
        }
        guard let count = session?.queuedPrompts.count, count > 0 else { return nil }
        return .count(count)
    }

    /// The agent and title (and project, when pinned away from it), then what the session is
    /// waiting on, so triage needs no click.
    private var tooltip: String {
        let project = indent == .flat ? model.projects.project(summary.project).map { " · \($0.name)" } : nil
        let line = "\(summary.agent.displayName) · \(title)\(project ?? "")\(isArchived ? " · Archived" : "")"
        let removed = model.removedWorkspaces[summary.id].map { "Its worktree was removed. \($0.detail)" }
        return [line, removed, session?.sidebarAsk].compactMap(\.self).joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        let removed = model.removedWorkspaces[summary.id] != nil ? "worktree removed" : nil
        let pullRequest = insights.pullRequestMenu(summary)?.spokenSummary
        return [title, removed, pullRequest, session?.sidebarAsk].compactMap(\.self).joined(separator: ", ")
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

    /// The sidebar asks first, in its one deletion dialog.
    private func requestDeletion() {
        picking?.deletionRequest = summary.id
    }

    private func archive() {
        Task { await model.archiveSession(summary.id, undoManager: undoManager) }
    }
}

// The list rebuilds its rows whenever it updates (a filter, a project's expansion, another
// session's change), and every rebuilt row would build its view again: a row's own changes reach it
// through what it observes, so a rebuilt row with the same inputs keeps its body. `accessory` is
// made from the summary and `select` only selects it, so they're left out.
extension SessionRow: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary == rhs.summary && lhs.indent == rhs.indent && lhs.isPinned == rhs.isPinned
            && lhs.canMoveUp == rhs.canMoveUp && lhs.canMoveDown == rhs.canMoveDown
    }
}

extension TaskStatus {
    /// How the sidebar shows a session: its status as every surface reads it
    /// (`SessionModel.taskStatus`). One that hasn't been opened in this run is idle.
    init(_ session: SessionModel?) {
        self = session?.taskStatus ?? .idle
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

#if DEBUG
#Preview("Task rows") {
    let app = AppModel.preview()
    DSPreviewPair {
        // Working, waiting for permission, done and unread, then two idle ones (one long).
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(SidebarPreviewFixtures.sessions(in: app)) { summary in
                SessionRow(summary: summary, canMoveUp: true, canMoveDown: true, accessory: EmptyView()) {}
            }
            ForEach(SidebarPreviewFixtures.sessions(in: app, project: 1)) { summary in
                SessionRow(summary: summary, canMoveUp: true, canMoveDown: true, accessory: EmptyView()) {}
            }
        }
        .frame(width: DS.Size.sidebarWidth - DS.Space.lg)
    }
    .sidebarPreviewEnvironment(app)
}
#Preview("Task rows - Agent icons hidden") {
    let app = AppModel.preview()
    let defaults = SidebarPreviewFixtures.defaults(showAgentIcons: false)
    DSPreviewPair {
        VStack(spacing: DS.Space.xxs) {
            ForEach(SidebarPreviewFixtures.sessions(in: app)) { summary in
                SessionRow(summary: summary, canMoveUp: true, canMoveDown: true, accessory: EmptyView()) {}
            }
        }
        .defaultAppStorage(defaults)
        .frame(width: DS.Size.sidebarWidth - DS.Space.lg)
    }
    .sidebarPreviewEnvironment(app)
}
#endif
