import ACP
import SwiftUI

@main
struct NativeApp: App {
    @State private var model: AppModel
    @State private var git: GitStore
    @State private var gitHub: GitHubModel
    @State private var iconPreferences = AppIconPreferences()

    init() {
        // Git and GitHub run with the login-shell environment the agents get.
        let model = AppModel()
        _model = State(initialValue: model)
        _git = State(initialValue: GitStore { await model.shellEnvironment() })
        _gitHub = State(initialValue: GitHubModel { await model.shellEnvironment(refresh: $0) })
    }

    var body: some Scene {
        Window("Native", id: "main") {
            RootView()
                .environment(model)
                .environment(git)
                .environment(gitHub)
                .createPullRequestSheet(gitHub)
                .dsAccentPalette(themeID: iconPreferences.theme.rawValue)
                .task {
                    OrchestrationPlugin.connect(to: model)
                    BuiltInPlugins.usage.limits.host = model
                    iconPreferences.start()
                    await model.start()
                }
                .task {
                    gitHub.openAsTask = { [model, git, weak gitHub] pullRequest in
                        guard let gitHub else { return }
                        try await GitHubGitWiring.openAsTask(pullRequest, app: model, git: git, gitHub: gitHub)
                    }
                    await gitHub.keepFresh()
                }
        }
        .defaultSize(width: 1120, height: 780)
        .commands {
            FileCommands(model: model)
            ViewCommands()
            GoCommands(model: model)
            SessionCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model.plugins)
                .environment(iconPreferences)
                .dsAccentPalette(themeID: iconPreferences.theme.rawValue)
                .task { iconPreferences.start() }
        }
        .windowResizability(.contentSize)
    }
}

// Every shortcut here is listed in `docs/keyboard.md`; change it there first.

private struct FileCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                Task { await model.newSession() }
            }
            .keyboardShortcut("n")
            .disabled(!model.canCreateSession())

            Button("New Session With…") {
                model.isChoosingAgent = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(model.projects.all.isEmpty || model.agents.isEmpty)

            Button("Open Folder…") {
                model.isAddingProject = true
            }
            .keyboardShortcut("o")
        }
    }
}

private struct ViewCommands: Commands {
    @FocusedValue(\.sidebarVisibility) private var sidebarVisibility
    @FocusedValue(\.activeSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(sidebarVisibility?.wrappedValue == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                guard let sidebarVisibility else { return }
                withAnimation {
                    sidebarVisibility.wrappedValue = sidebarVisibility.wrappedValue == .detailOnly ? .all : .detailOnly
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(sidebarVisibility == nil)

            Button("Toggle Subagent Inspector") {
                session?.isSubagentInspectorToggleRequested = true
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(session?.state.subagents.isEmpty ?? true)

            GitChangesMenuItem()
        }
    }
}

private struct GoCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            Button("Back") {
                model.goBack()
            }
            .keyboardShortcut("[")
            .disabled(!model.canGoBack)

            Button("Forward") {
                model.goForward()
            }
            .keyboardShortcut("]")
            .disabled(!model.canGoForward)

            Divider()
            PullRequestsMenuItem()
        }
    }
}

private struct SessionCommands: Commands {
    let model: AppModel
    @FocusedValue(\.activeSession) private var session
    @FocusedValue(\.sidebarReorder) private var reorder

    var body: some Commands {
        CommandMenu("Session") {
            Button("Focus Composer") {
                session?.wantsComposerFocus = true
                session?.focusComposerRequest += 1
            }
            .keyboardShortcut("l")
            .disabled(session == nil || session?.isSubagent == true)

            Button("Stop") {
                Task { await session?.cancel() }
            }
            .keyboardShortcut(".")
            .disabled(session?.canCancel != true)

            Divider()

            Button("Next Permission Mode") {
                guard let session else { return }
                Task { await nextPermissionMode(of: session) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(session.map { ComposerSettings($0.state.configOptions).autonomy == nil } ?? true)

            Button("Choose Model…") {
                session?.isModelPickerRequested = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(session.map { ComposerSettings($0.state.configOptions).model == nil } ?? true)

            Divider()

            Button("Rename Session…") {
                model.renaming = model.selection
            }
            .disabled(model.selection == nil)

            Button("Move Up") {
                reorder?.move(.up)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(reorder?.canMove(.up) != true)

            Button("Move Down") {
                reorder?.move(.down)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(reorder?.canMove(.down) != true)

            Button("Next Session") {
                model.selectSession(offset: 1)
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(model.sessionList.isEmpty)

            Button("Previous Session") {
                model.selectSession(offset: -1)
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(model.sessionList.isEmpty)

            let shortcuts = Array(model.sessionList.prefix(9).enumerated())
            if !shortcuts.isEmpty {
                Divider()
                ForEach(shortcuts, id: \.element.id) { index, listed in
                    Button(model.title(for: listed)) {
                        model.selection = listed.id
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }
    }

    /// Moves the permission mode one step up the autonomy scale, wrapping around; Plan Mode isn't a step.
    private func nextPermissionMode(of session: SessionModel) async {
        guard let change = ComposerSettings(session.state.configOptions).nextAutonomy else { return }
        await session.setConfigOption(change.setting.option, to: change.value)
    }
}
