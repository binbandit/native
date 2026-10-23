import NativeCommands
import SwiftUI
import Undo

/// The menu bar. Its menus place commands; what each does, when it's available and its shortcut
/// come from the registry (docs/commands.md). Default shortcuts are in docs/keyboard.md; change them
/// there first.
///
/// It reads the frontmost window's context once and hands it to every menu, rather than each of its
/// items reading eight focused values of its own.
struct NativeMenuBar: Commands {
    let model: AppModel
    let settings: SettingsPresentation
    let host: DurableHost
    let projectActions: ProjectActionRunner
    let keepAwake: KeepAwakeController
    let statusBar: StatusBarRegistry
    private let registry = CommandRegistry.shared
    @FocusedCommandContext private var context

    var body: some Commands {
        let menu = CommandMenuContext(registry: registry, context: windowContext)
        WindowUndoCommands(history: model.undoHistory)
        #if os(macOS)
        PlatformWindowCloseCommands()
        UpdateCommands(menu: menu)
        HostQuitCommands(host: host, menu: menu)
        #endif
        WhatsNewCommands(menu: menu)
        HelpCommands(menu: menu, model: model)
        FileCommands(menu: menu)
        ViewCommands(menu: menu)
        AppearanceCommands(menu: menu)
        SettingsCommands(settings: settings)
        GoCommands(menu: menu)
        SessionCommands(model: model, menu: menu)
        ProjectActionCommands(
            runner: projectActions, menu: menu,
            target: { [model] in ProjectActionsWiring.target(for: $0, model: model) })
        TerminalCommands(menu: menu)
        KeepAwakeCommands(controller: keepAwake, menu: menu)
        StatusBarCommands(registry: statusBar, menu: menu)
    }

    private var windowContext: CommandContext {
        var context = context
        context.windowUndoManager = model.undoHistory.manager
        return context
    }
}

private struct FileCommands: Commands {
    let menu: CommandMenuContext

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            CommandMenuItem(.sessionNew, in: menu)
            CommandMenuItem(.sessionNewWithAgent, in: menu)
            CommandMenuItem(.expeditionNew, in: menu)
            CommandMenuItem(.projectOpen, in: menu)
            CommandMenuItem(.projectSettings, in: menu)
            CommandMenuItem(.pullRequestOpenAsTask, in: menu)
            CommandMenuItem(.gitCleanUpMerged, in: menu)
            Divider()
            CommandMenuItem(.composerAttachFiles, in: menu)
        }
    }
}

private struct ViewCommands: Commands {
    let menu: CommandMenuContext

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            CommandMenuItem(.paletteShow, in: menu)
            Divider()
            CommandMenuItem(.viewToggleSidebar, in: menu)
            CommandMenuItem(.viewToggleSubagentInspector, in: menu)
            CommandMenuItem(.viewToggleChanges, in: menu)
            if menu.context.sessionTools != nil {
                Menu("Tools") {
                    CommandMenuItem(.sessionToolChanges, in: menu)
                }
            }
            CommandMenuItem(.viewMCPServers, in: menu)
            CommandMenuItem(.viewNeedsYouFilter, in: menu)

            Divider()
            // Its own toggle, so the checkmark follows the preference; the shortcut is the registry's.
            FoldEarlierTurnsToggle()
                .keyboardShortcut(menu.registry.keyboardShortcut(for: .transcriptFoldEarlierTurns))
            CommandMenuItem(.transcriptJumpToLatest, in: menu)

            Divider()
            CommandMenuItem(.celebrationRestore, in: menu)
            CommandMenuItem(.celebrationChoose, in: menu)
        }
    }
}

private struct SettingsCommands: Commands {
    let settings: SettingsPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ⌘, is macOS's standard Settings key, so it stays outside the registry.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                // Settings lives in the main window, so bring the window back if it was closed.
                openWindow(id: NativeWindowID.main)
                settings.toggle()
            }
            .keyboardShortcut(",")
        }
    }
}

private struct GoCommands: Commands {
    let menu: CommandMenuContext

    var body: some Commands {
        CommandMenu("Go") {
            CommandMenuItem(.goBack, in: menu)
            CommandMenuItem(.goForward, in: menu)
            Divider()
            CommandMenuItem(.goPullRequests, in: menu)
            #if os(macOS)
            CommandMenuItem(.gitHubAccounts, in: menu)
            #endif
            CommandMenuItem(.goExpeditions, in: menu)
            TranscriptSearchMenuItem(menu: menu)
        }
    }
}

private struct SessionCommands: Commands {
    let model: AppModel
    let menu: CommandMenuContext

    var body: some Commands {
        CommandMenu("Task") {
            CommandMenuItem(.composerFocus, in: menu)
            CommandMenuItem(.sessionStop, in: menu)
            CommandMenuItem(.sessionClearConversation, in: menu)
            if model.offersAgentChange { CommandMenuItem(.sessionChangeAgent, in: menu) }
            CommandMenuItem(.sessionOpenEarlierConversation, in: menu)
            CommandMenuItem(.sessionOpenCurrentConversation, in: menu)

            Divider()

            CommandMenuItem(.sessionNextPermissionMode, in: menu)
            ModeMenuItems(menu: menu)
            CommandMenuItem(.sessionChooseModel, in: menu)

            Divider()

            // The visible task's folder (its worktree when it has one); disabled while no task is in
            // view (Home, Settings, Pull Requests).
            OpenInCommands(
                location: menu.context.session.map {
                    OpenInLocation(folder: $0.cwd, host: model.currentProject?.host ?? .local)
                },
                menu: menu)
            CommandMenuItem(.pullRequestOpenForTask, in: menu)

            Divider()

            CommandMenuItem(.goalEdit, in: menu)
            CommandMenuItem(.goalPauseOrResume, in: menu)
            CommandMenuItem(.goalClear, in: menu)
            CommandMenuItem(.workflowRun, in: menu)

            Divider()

            CommandMenuItem(.sessionRename, in: menu)
            CommandMenuItem(.sessionArchive, in: menu)
            CommandMenuItem(.sessionTogglePin, in: menu)
            CommandMenuItem(.sessionToggleUnread, in: menu)
            Menu("Selected Tasks") {
                CommandMenuItem(.sidebarSelectMode, in: menu)
                CommandMenuItem(.sidebarSelectAll, in: menu)
                CommandMenuItem(.selectionClear, in: menu)
                Divider()
                CommandMenuItem(.selectionMarkRead, in: menu)
                CommandMenuItem(.selectionMarkUnread, in: menu)
                CommandMenuItem(.selectionPin, in: menu)
                CommandMenuItem(.selectionUnpin, in: menu)
                CommandMenuItem(.selectionStop, in: menu)
                Divider()
                CommandMenuItem(.selectionArchive, in: menu)
                CommandMenuItem(.selectionUnarchive, in: menu)
                CommandMenuItem(.selectionDelete, in: menu)
            }
            CommandMenuItem(.sidebarMoveUp, in: menu)
            CommandMenuItem(.sidebarMoveDown, in: menu)
            CommandMenuItem(.sessionNext, in: menu)
            CommandMenuItem(.sessionPrevious, in: menu)

            let listed = min(model.sessionList.count, CommandID.sessionSelectPositions.upperBound)
            if listed > 0 {
                Divider()
                ForEach(1...listed, id: \.self) { position in
                    CommandMenuItem(.sessionSelect(position), in: menu)
                }
            }
        }
    }
}
