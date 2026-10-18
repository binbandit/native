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
            NativeCommand(.sessionNew, title: "New Session", category: .tasks, systemImage: "square.and.pencil") { _ in
                Task { await model.newSession() }
            }
            // Never disabled otherwise: without a project or an agent, New Session says what's missing.
            .available { _ in !model.isCreatingSession },

            NativeCommand(
                .sessionNewWithAgent, title: "New Session With…", category: .tasks,
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
            NativeCommand(.sessionRename, title: "Rename Session…", category: .tasks, systemImage: "pencil") { _ in
                model.renaming = model.selection
            }
            .available { _ in model.selection != nil },

            NativeCommand(.sessionArchive, title: "Archive Task", category: .tasks, systemImage: "archivebox") {
                context in
                guard let key = model.selection else { return }
                Task { await model.archiveSession(key, undoManager: context.undoManager) }
            }
            .available { _ in model.selection != nil },

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
            // and while the sidebar is hidden.
            NativeCommand(.sidebarMoveUp, title: "Move Up", category: .tasks, systemImage: "arrow.up") { _ in
                model.sidebarMoveTarget.map { model.move($0, .up) }
            }
            .available { _ in model.sidebarMoveTarget.map { model.canMove($0, .up) } == true },

            NativeCommand(.sidebarMoveDown, title: "Move Down", category: .tasks, systemImage: "arrow.down") { _ in
                model.sidebarMoveTarget.map { model.move($0, .down) }
            }
            .available { _ in model.sidebarMoveTarget.map { model.canMove($0, .down) } == true },

            NativeCommand(.sessionNext, title: "Next Session", category: .navigation, systemImage: "chevron.down") {
                _ in
                model.selectSession(offset: 1)
            }
            .available { _ in !model.sessionList.isEmpty },

            NativeCommand(
                .sessionPrevious, title: "Previous Session", category: .navigation, systemImage: "chevron.up"
            ) { _ in
                model.selectSession(offset: -1)
            }
            .available { _ in !model.sessionList.isEmpty },
        ]
            + CommandID.sessionSelectPositions.map { position in
                NativeCommand(.sessionSelect(position), title: "Go to Session \(position)", category: .navigation) {
                    _ in
                    guard let listed = model.sessionList.dropFirst(position - 1).first else { return }
                    model.selection = listed.id
                }
                .menuTitle { _ in model.sessionList.dropFirst(position - 1).first.map(model.title(for:)) ?? "" }
                .available { _ in model.sessionList.count >= position }
                // The palette lists the tasks themselves, by name.
                .hiddenFromPalette()
            }
    }
}
