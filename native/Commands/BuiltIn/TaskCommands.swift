import ACP
import NativeCommands

extension CommandID {
    static let sessionNew: Self = "session.new"
    static let sessionNewWithAgent: Self = "session.newWithAgent"
    static let projectOpen: Self = "project.open"
    static let sessionRename: Self = "session.rename"
    static let sessionArchive: Self = "session.archive"
    static let sessionTogglePin: Self = "session.togglePin"
    static let sessionToggleUnread: Self = "session.toggleUnread"
    static let sidebarMoveUp: Self = "sidebar.moveUp"
    static let sidebarMoveDown: Self = "sidebar.moveDown"
    static let sessionNext: Self = "session.next"
    static let sessionPrevious: Self = "session.previous"

    /// ⌘1 – ⌘9: the Nth session in the sidebar.
    static func sessionSelect(_ position: Int) -> Self {
        Self("session.select\(position)")
    }

    static let sessionSelectPositions = 1...9
}

extension NativeCommand {
    /// Starting tasks and opening projects.
    static func newTasks(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(.sessionNew, title: "New Task", category: .tasks, systemImage: "square.and.pencil") { _ in
                if model.homeNextOwnsNewTask {
                    model.homeNext.startFieldFocusRequests &+= 1
                } else if model.quickEntry.isEnabled {
                    model.showQuickEntry(selection: PlatformTextSelection.capture())
                } else {
                    Task { await model.newSession() }
                }
            },

            NativeCommand(
                .sessionNewWithAgent, title: "New Task With…", category: .tasks,
                systemImage: "plus.square.on.square",
                keywords: ["agent"]
            ) { _ in
                model.isChoosingAgent = true
            }
            .available { _ in !model.projects.all.isEmpty && !model.agents.isEmpty },

            NativeCommand(
                .projectOpen, title: "Open Folder…", category: .tasks, systemImage: "folder.badge.plus",
                keywords: ["project", "add"]
            ) { _ in
                model.isAddingProject = true
            },
        ]
    }

    /// What to do with the selected task, and moving between tasks.
    static func taskActions(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(.sessionRename, title: "Rename Task…", category: .tasks, systemImage: "pencil") { _ in
                model.renaming = model.selection
            }
            .available { _ in model.selection != nil },

            // The same command brings back an archived task opened from the archive.
            NativeCommand(
                .sessionArchive, title: "Archive or Unarchive Task", category: .tasks, systemImage: "archivebox"
            ) { context in
                // With several tasks picked in the sidebar, it archives them all.
                if let keys = context.sidebarSelection?.keys, keys.count > 1 {
                    context.sidebarSelection?.clear()
                    Task { await model.archiveSessions(keys, undoManager: context.undoManager) }
                    return
                }
                guard let key = model.selection else { return }
                if model.isArchived(key) {
                    Task { await model.unarchiveSession(key) }
                } else {
                    Task { await model.archiveSession(key, undoManager: context.undoManager) }
                }
            }
            .menuTitle { context in
                if let count = context.sidebarSelection?.keys.count, count > 1 { return "Archive \(count) Tasks" }
                return model.selection.map(model.isArchived) == true ? "Unarchive Task" : "Archive Task"
            }
            .available { context in model.selection != nil || (context.sidebarSelection?.keys.count ?? 0) > 1 },

            NativeCommand(.sessionTogglePin, title: "Pin or Unpin Task", category: .tasks, systemImage: "pin") {
                context in
                guard let key = model.selection else { return }
                model.setPinned(key, !model.isPinned(key), undoManager: context.undoManager)
            }
            .menuTitle { _ in model.selection.map(model.isPinned) == true ? "Unpin Task" : "Pin Task" }
            .available { _ in model.selection != nil },

            NativeCommand(
                .sessionToggleUnread, title: "Mark as Read or Unread", category: .tasks, systemImage: "circlebadge"
            ) { _ in
                guard let key = model.selection else { return }
                model.setUnread(key, !model.isUnread(key))
            }
            .menuTitle { _ in model.selection.map(model.isUnread) == true ? "Mark as Read" : "Mark as Unread" }
            .available { _ in model.selection != nil },

            // From the model rather than the sidebar's focused value, so they work wherever focus is
            // and while the sidebar is hidden. While a queued message is open in the composer, they
            // move it in the queue instead.
            NativeCommand(.sidebarMoveUp, title: "Move Up", category: .tasks, systemImage: "arrow.up") { context in
                if let session = context.session, let id = session.editingQueuedPrompt {
                    session.moveQueued(id, .up)
                } else {
                    model.sidebarMoveTarget.map { model.move($0, .up) }
                }
            }
            .menuTitle { $0.session?.editingQueuedPrompt == nil ? "Move Up" : "Move Queued Message Up" }
            .available { context in
                if let session = context.session, let id = session.editingQueuedPrompt {
                    return session.canMoveQueued(id, .up)
                }
                return model.sidebarMoveTarget.map { model.canMove($0, .up) } == true
            },

            NativeCommand(.sidebarMoveDown, title: "Move Down", category: .tasks, systemImage: "arrow.down") {
                context in
                if let session = context.session, let id = session.editingQueuedPrompt {
                    session.moveQueued(id, .down)
                } else {
                    model.sidebarMoveTarget.map { model.move($0, .down) }
                }
            }
            .menuTitle { $0.session?.editingQueuedPrompt == nil ? "Move Down" : "Move Queued Message Down" }
            .available { context in
                if let session = context.session, let id = session.editingQueuedPrompt {
                    return session.canMoveQueued(id, .down)
                }
                return model.sidebarMoveTarget.map { model.canMove($0, .down) } == true
            },

            NativeCommand(.sessionNext, title: "Next Task", category: .navigation, systemImage: "chevron.down") {
                _ in
                model.selectSession(offset: 1)
            }
            .available { _ in !model.sidebarNavigationOrder.isEmpty },

            NativeCommand(
                .sessionPrevious, title: "Previous Task", category: .navigation, systemImage: "chevron.up"
            ) { _ in
                model.selectSession(offset: -1)
            }
            .available { _ in !model.sidebarNavigationOrder.isEmpty },
        ]
            + CommandID.sessionSelectPositions.map { position in
                NativeCommand(.sessionSelect(position), title: "Go to Task \(position)", category: .navigation) {
                    _ in
                    guard let key = model.sidebarNavigationOrder.dropFirst(position - 1).first else { return }
                    model.selection = key
                }
                .menuTitle { _ in
                    model.sidebarNavigationOrder.dropFirst(position - 1).first.map(model.titleOfSession) ?? ""
                }
                .available { _ in model.sidebarNavigationOrder.count >= position }
                // The palette lists the tasks themselves, by name.
                .hiddenFromPalette()
            }
    }
}
