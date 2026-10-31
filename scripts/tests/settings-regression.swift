import ACP
import CodeThemes
import Experiments
import Foundation
import Modes
import NativeHostProtocol
import NativePolicy
import Skills
import TaskDefaults

@testable import Native

@MainActor
private final class InertKeepAwakeEngine: KeepAwakeEngine {
    var onChange: ((KeepAwakeStatus) -> Void)?
    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus { .off }
    func stop() {}
}

@main
@MainActor
struct SettingsRegression {
    private static var failures = 0

    static func main() async {
        let preferences = SoundPreferences(defaults: PreviewUserDefaults())
        let sounds = NotificationSounds(preferences: preferences)
        #if BEFORE
        let registry = PluginRegistry(builtIns: [SoundsPlugin(sounds: sounds)])
        registry.setEnabled(false, for: "sounds")
        expect(preferences.isEnabled == registry.isEnabled("sounds"), "Sound switches agree")
        #else
        let registry = PluginRegistry(builtIns: [SoundsPlugin(sounds: sounds)], defaults: PreviewUserDefaults())
        await soundChoices()
        #endif
        navigation(registry: registry)
        #if !BEFORE
        newTasksDefaults()
        await startingModeAtLaunch()
        worktreeContextReports()
        await effectiveInstructionEnvironment()
        await instructionScope()
        plainlyNavigation()
        combinedLibraryScope()
        accountNavigation()
        codeThemeChoices()
        await themeTryOn()
        #endif
        if failures > 0 {
            print("FAILED: \(failures) Settings regressions")
            exit(1)
        }
        print(
            "PASS: Settings navigation, account links, code theme choices, Try On, sound migration, live switching and disabled playback"
        )
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            print("FAIL: \(message)")
            failures += 1
        }
    }

    private static func navigation(registry: PluginRegistry) {
        let keepAwake = KeepAwakeController(engine: InertKeepAwakeEngine(), defaults: PreviewUserDefaults())
        let panes =
            SettingsPane.builtIn(registry: registry)
            + AppSettingsPanes.all(plugins: registry, terminals: TerminalStore(), keepAwake: keepAwake, projects: [])
        for (group, entries) in Dictionary(grouping: panes, by: \.group) {
            expect(Set(entries.map(\.order)).count == entries.count, "Unique positions in \(group.title)")
        }
        let titles = panes.sorted { ($0.group, $0.order) < ($1.group, $1.order) }.map(\.title)
        expect(
            titles == [
                "General", "Appearance", "Sounds", "Notifications", "Keep Awake", "Terminal", "Search",
                "Keyboard shortcuts", "Privacy", "Agents", "Background", "Hosts", "Git", "Usage", "GitHub",
                "Modes", "AI Instructions", "Scripts", "Extensions", "Labs", "MCP Servers", "Skills",
                "Celebrations", "Paired Devices", "Updates",
            ], "Keep the existing visible page order: \(titles)")
    }

    #if !BEFORE
    private static func newTasksDefaults() {
        let defaults = PreviewUserDefaults()
        let id = AgentDefinition.ID(rawValue: "fixture-agent")
        let project = Project(url: URL(filePath: "/tmp/native-newtasks-fixture"))
        let optionsJSON = """
            [{"id":"model","name":"Model","category":"model","type":"select","currentValue":"agent",
            "options":[{"value":"agent","name":"Agent model"},{"value":"user","name":"User model"},{"value":"project","name":"Project model"}]},
            {"id":"permission","name":"Permissions","category":"mode","type":"select","currentValue":"ask",
            "options":[{"value":"ask","name":"Ask before edits"},{"value":"edit","name":"Edit files"},{"value":"auto","name":"Auto"}]}]
            """
        guard let options = try? JSONDecoder().decode([ConfigOption].self, from: Data(optionsJSON.utf8)) else {
            expect(false, "Decode new-task wire fixture"); return
        }
        AgentSessionDefaults.remember(options, for: id, isNew: true, defaults: defaults)
        let global = NewTasksDefaultsModel(agent: id, agentName: "Fixture", project: nil, defaults: defaults)
        let local = NewTasksDefaultsModel(agent: id, agentName: "Fixture", project: project, defaults: defaults)
        global.set("user", for: .model)
        local.set("project", for: .model)
        expect(local.receipt(.model, policy: .default).value == "Project model", "Project source wins")
        expect(
            global.receipt(.model, policy: .default).value == "User model", "Project changes leave All projects alone")
        local.set(nil, for: .model)
        expect(local.receipt(.model, policy: .default).value == "User model", "Reset follows All projects")
        let reopened = NewTasksDefaultsModel(agent: id, agentName: "Fixture", project: project, defaults: defaults)
        expect(
            reopened.receipt(.model, policy: .default).value == "User model", "Defaults persist when the page reopens")
        local.set("gone", for: .model)
        expect(
            local.receipt(.model, policy: .default).value == "Agent model",
            "Unavailable project value keeps the agent default")
        local.set(nil, for: .model)
        global.set("gone", for: .model)
        let inherited = local.receipt(.model, policy: .default)
        expect(
            inherited.unavailable && inherited.unavailableNote?.contains("set for All projects") == true
                && local.stored(.model) == nil,
            "A project explains an unavailable choice it inherits, without a project value to reset")
        global.set("user", for: .model)
        defaults.set("default", forKey: "agentDefaults.\(id.rawValue).permissions")
        expect(TaskPermissionDefaults.value(defaults: defaults) == .askFirst, "Legacy permission defaults migrate")
        expect(
            AgentSessionDefaults.configuredValues(for: id, defaults: defaults)["mode"] == nil,
            "Shared defaults never change reopened tasks")
        let modes = ModeLibrary(defaults: defaults)
        modes.setStartingMode(.plan, forProjectAt: project.url)
        expect(
            modes.startingMode.id == .build && modes.startingMode(forProjectAt: project.url).id == .plan,
            "Starting mode is scoped to one project")
        let undo = UndoManager()
        ProjectTaskDefaults.setAgent(id, for: project.id, defaults: defaults, undoManager: undo)
        undo.undo()
        expect(
            ProjectTaskDefaults.agent(for: project.id, defaults: defaults) == nil, "Undo restores the starting agent")
        modes.setStartingMode(.build, forProjectAt: project.url, undoManager: undo)
        undo.undo()
        expect(modes.startingMode(forProjectAt: project.url).id == .plan, "Undo restores the project's starting mode")
        modes.setStartingMode(.init(rawValue: "removed-mode"), forProjectAt: project.url)
        expect(modes.startingMode(forProjectAt: project.url).id == .build, "A removed mode follows All projects")
        let git = GitSettings(defaults: defaults)
        git.setStartingWorkspace(.branch, project: project.url)
        expect(
            git.newTaskWorkspace == .worktree && git.newTaskWorkspace(forProjectAt: project.url) == .branch,
            "Workspace override leaves All projects alone")
        let presentation = SettingsPresentation()
        presentation.openNewTasks(agent: id)
        expect(
            presentation.takeAgentScope() == id && presentation.takeAgentScope() == nil,
            "Agent links select a scope once")
        AgentSessionDefaults.remember(Array(options.prefix(1)), for: id, defaults: defaults)
        global.refresh()
        expect(global.choices(.effort).isEmpty, "Removed agent options clear their cached choices")
    }

    /// A task starts before the catalog lists it under its project, so the launch hands over the
    /// project's folder. Global Build with project Plan must start the task in Plan.
    private static func startingModeAtLaunch() async {
        expect(ExperimentStore.shared.value(of: .settingsPlainly), "The runner turns Plainly on")
        let defaults = PreviewUserDefaults()
        let folder = URL.temporaryDirectory.appending(path: "native-starting-mode-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.codex], defaults: defaults), defaults: defaults,
            catalogURL: nil, experiments: ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage()))
        _ = app.runtimes.sync()
        let project = app.projects.add(folder)
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        modes.projectRoot = { session in
            app.catalog.lookup(session.key).flatMap { app.projects.project($0.project)?.url }
        }
        modes.library.setStartingMode(.plan, forProjectAt: project.url)
        guard let session = SessionModel.preview(in: app, agent: "codex", cwd: folder.path) else {
            expect(false, "Make a starting session"); return
        }
        expect(modes.projectRoot(session) == nil, "The catalog does not list a task that is still starting")
        await modes.taskStarted(session, continuing: nil, projectRoot: project.url)
        expect(modes.library.startingMode.id == .build, "All projects still start in Build")
        expect(modes.mode(of: session).id == .plan, "The project's starting mode applies at launch")
        expect(modes.preamble(for: session, delivered: nil) != nil, "Plan's instructions go with the first prompt")
    }

    /// A task in a worktree works outside the project's checkout but still reports for its project.
    private static func worktreeContextReports() {
        let defaults = PreviewUserDefaults()
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.codex], defaults: defaults), defaults: defaults,
            catalogURL: nil, experiments: ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage()))
        _ = app.runtimes.sync()
        let selected = app.projects.add(URL(filePath: "/fixture/reports/selected"))
        let other = app.projects.add(URL(filePath: "/fixture/reports/other"))
        let optionsJSON = """
            [{"id":"model","name":"Model","category":"model","type":"select","currentValue":"sol",
            "options":[{"value":"sol","name":"Sol"}]}]
            """
        guard let options = try? JSONDecoder().decode([ConfigOption].self, from: Data(optionsJSON.utf8)) else {
            expect(false, "Decode report wire fixture"); return
        }
        let codex = AgentDefinition.ID(rawValue: "codex")
        func task(_ id: String, in project: Project, cwd: String) -> SessionModel? {
            app.catalog.add(SessionInfo(sessionId: SessionID(id), cwd: cwd, title: id), for: codex, in: project.id)
            return SessionModel.preview(in: app, agent: "codex", id: id, cwd: cwd, configOptions: options)
        }
        let worktree = task("worktree", in: selected, cwd: "/fixture/worktrees/selected/task")
        _ = task("elsewhere", in: other, cwd: "/fixture/reports/other")
        let matches = NewTasksScopedContent.sessions(in: app, agent: codex, project: selected.id, model: "Sol")
        expect(
            matches.map(\.key) == [worktree?.key].compactMap { $0 },
            "Reports come from the project's worktree tasks and no other project's")
    }

    /// The agent's own environment (its plugin's `env`) says where it reads instructions, over the shell's.
    private static func effectiveInstructionEnvironment() async {
        let root = URL.temporaryDirectory.appending(path: "native-instruction-env-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let shell = root.appending(path: "shell")
        let agentHome = root.appending(path: "agent")
        for folder in [shell, agentHome] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data("instructions in \(folder.lastPathComponent)".utf8).write(to: folder.appending(path: "AGENTS.md"))
        }
        let agent = AgentManifest(
            id: "fixture", name: "Fixture", command: "/usr/bin/true", env: ["FIXTURE_HOME": agentHome.path],
            instructionLocations: [.init(scope: .user, environmentKey: "FIXTURE_HOME", names: ["AGENTS.md"])])
        let registry = PluginRegistry(
            builtIns: [ManifestPlugin(manifest: PluginManifest(id: "fixture", name: "Fixture", agents: [agent]))],
            defaults: PreviewUserDefaults())
        let loads = NewTasksLoadsModel(agent: agent, project: nil, registry: registry)
        await loads.readInstructions(shellEnvironment: ["HOME": shell.path, "FIXTURE_HOME": shell.path])
        expect(
            loads.instructions.map { $0.url.deletingLastPathComponent().lastPathComponent } == ["agent"],
            "Only the instruction files in the agent's own folder are listed")
    }

    /// A project's own instruction files belong to that project: never listed for All projects
    /// or for another project.
    private static func instructionScope() async {
        let root = URL.temporaryDirectory.appending(path: "native-instruction-scope-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pier = root.appending(path: "pier")
        let native = root.appending(path: "native")
        for folder in [pier, native] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try? Data("pier's instructions".utf8).write(to: pier.appending(path: "AGENTS.md"))
        let agent = AgentManifest(
            id: "fixture", name: "Fixture", command: "/usr/bin/true",
            instructionLocations: [.init(scope: .project, names: ["AGENTS.md"])])
        let registry = PluginRegistry(
            builtIns: [ManifestPlugin(manifest: PluginManifest(id: "fixture", name: "Fixture", agents: [agent]))],
            defaults: PreviewUserDefaults())
        func listed(in project: Project?) async -> [String] {
            let loads = NewTasksLoadsModel(agent: agent, project: project, registry: registry)
            await loads.readInstructions(shellEnvironment: ["HOME": root.path])
            return loads.instructionItems.map { "\($0.name) · \($0.source)" }
        }
        let pierProject = Project(url: pier)
        expect(await listed(in: nil).isEmpty, "All projects lists no project's own instructions")
        expect(await listed(in: Project(url: native)).isEmpty, "Another project doesn't list pier's instructions")
        expect(
            await listed(in: pierProject) == ["AGENTS.md · \(pierProject.name)"],
            "pier lists its own instructions, named for it")
    }

    private static func accountNavigation() {
        let presentation = SettingsPresentation()
        let row = GitHubAccountsSettingsSection.accountsRow
        presentation.open(.general, revealing: row)
        expect(presentation.pane == .general && presentation.rowReveal?.rowID == row, "Account links reveal General")
        let first = presentation.rowReveal
        presentation.open(.general, revealing: row)
        expect(presentation.rowReveal != first, "Repeated account links reveal the row again")
        presentation.pane = .appearance
        expect(presentation.rowReveal == nil, "Navigating away clears the account reveal")
        presentation.open(.general, revealing: row)
        presentation.close()
        presentation.open()
        expect(presentation.rowReveal == nil, "Opening Settings normally does not replay an old account link")
        let index = SettingsSearchIndex(panes: [.general, .gitHub])
        expect(
            index.results(for: "GitHub accounts", limit: 1).first?.item.rowID == row,
            "Account search reveals the General group with Plainly off")
    }

    private static func combinedLibraryScope() {
        let presentation = SettingsPresentation()
        let project = URL(filePath: "/tmp/native-settings-project")
        let folder = URL.temporaryDirectory.appending(path: "native-settings-skills-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = SkillLibrary(supportFolder: folder)
        for intended in [SettingsPane.ID.skills, .mcpServers] {
            for first in [SettingsPane.ID.skills, .mcpServers] {
                presentation.open(intended, scopedTo: project)
                let second: SettingsPane.ID = first == .skills ? .mcpServers : .skills
                let firstScope = presentation.takeProjectScope(for: first)
                let secondScope = presentation.takeProjectScope(for: second)
                let target = intended == first ? firstScope : secondScope
                let sibling = intended == first ? secondScope : firstScope
                expect(target == project && sibling == nil, "Only the intended library consumes a project scope")
                expect(presentation.projectScope == nil, "A project scope is consumed once")
                if intended == .skills {
                    let key = "fixture-\(first.rawValue)"
                    library.setMode(.off, for: key, in: target)
                    let reopened = SkillLibrary(supportFolder: folder)
                    expect(
                        reopened.mode(of: key, in: project) == .off, "Skills changes persist for the requested project")
                    expect(
                        reopened.mode(of: key, in: nil) == .on, "A project Skills change leaves the global switch on")
                }
            }
        }
        presentation.open(.newTasks, scopedTo: project)
        expect(presentation.takeProjectScope(for: .skills) == nil, "Libraries leave New Tasks scope alone")
        expect(presentation.takeProjectScope(for: .newTasks) == project, "New Tasks receives its project")
        presentation.open(.skills, scopedTo: project)
        presentation.open(.skills)
        expect(presentation.takeProjectScope(for: .skills) == nil, "An unscoped visit cancels a pending scope")
        presentation.open(.skills, scopedTo: project)
        presentation.pane = .general
        expect(presentation.projectScope == nil, "Navigation clears an unconsumed scope")
    }

    private static func plainlyNavigation() {
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        expect(!experiments.value(of: .settingsPlainly), "Plainly defaults off")
        let registry = PluginRegistry(
            builtIns: [BuiltInPlugins.codex, SoundsPlugin(), MCPServersPlugin(), SkillsPlugin()],
            defaults: PreviewUserDefaults())
        let keepAwake = KeepAwakeController(engine: InertKeepAwakeEngine(), defaults: PreviewUserDefaults())
        let source =
            SettingsPane.builtIn(registry: registry)
            + AppSettingsPanes.all(plugins: registry, terminals: TerminalStore(), keepAwake: keepAwake, projects: [])
        let legacy = SettingsPageMap.panes(source, registry: registry, plainly: false)
        expect(Set(legacy.map(\.id)) == Set(source.map(\.id)), "Switch off preserves every page")
        registry.setEnabled(false, for: MCPServersPlugin.id)
        registry.setEnabled(false, for: SkillsPlugin.id)
        let panes = SettingsPageMap.panes(source, registry: registry, plainly: true)
        expect(
            panes.map(\.title) == [
                "General", "Appearance", "Notifications", "Keyboard", "Privacy",
                "New Tasks", "Agents", "While You're Away", "Writing Style",
                "Git", "Terminal", "Search", "Usage", "Features", "Labs", "Updates",
            ], "Approved map plus retained Usage and Labs")
        for (group, entries) in Dictionary(grouping: panes, by: \.group) {
            expect(Set(entries.map(\.order)).count == entries.count, "Plainly order is unique in \(group.title)")
        }
        let index = SettingsSearchIndex(panes: panes)
        func row(_ id: SettingsRowID, title: String, page: SettingsPane.ID) {
            let matches = index.items.filter { $0.rowID == id }
            expect(
                matches.count == 1 && matches.first?.title == title && matches.first?.paneID == page,
                "\(title) has one search result at its new home")
        }
        row(GeneralSettingsPage.followUpRow, title: "Return", page: .general)
        row(GitHubAccountsSettingsSection.accountsRow, title: "GitHub accounts", page: .general)
        row(NotificationSettingsPage.dockBadgeRow, title: "Badge", page: .general)
        row(NotificationSettingsPage.thresholdRow, title: "After turns longer than", page: .notifications)
        row(GitSettingsPage.workspaceRow, title: "Work in", page: .newTasks)
        row(.modesDefault, title: "Mode", page: .newTasks)
        row(GitHubSettingsPage.openingRow, title: "Open pull requests", page: .git)
        row(KeepAwakeSettingsPage.modeRow, title: "Keep Mac awake", page: .background)
        row(BackgroundSettingsPage.keepRunningRow, title: "Keep agents running after you quit", page: .background)
        row(TerminalSettingsPage.colorsRow, title: "Colors", page: .terminal)
        row(PrivacySettingsPage.idRow, title: "Installation ID", page: .privacy)
        row(
            AgentDefaultsRow.settingRowID(agentID: .init(rawValue: "codex"), setting: .model), title: "Model",
            page: .newTasks)
        expect(
            index.results(for: "Codex model", limit: 1).first?.item.location == "New Tasks ▸ Codex",
            "Model results name the agent while keeping the row's title")
        expect(SettingsPageMap.destination(.scripts) == .git, "Existing Scripts links open Git")
        expect(SettingsPageMap.destination(.pairedDevices) == .background, "Device links open While You're Away")
        expect(panes.contains { $0.id == .usage }, "The activity graph stays in Settings")
        registry.setEnabled(true, for: MCPServersPlugin.id)
        registry.setEnabled(true, for: SkillsPlugin.id)
        let withTools = SettingsPageMap.panes(source, registry: registry, plainly: true)
        expect(withTools.filter { $0.id == .toolsSkills }.count == 1, "Tools and skills share one destination")
        expect(!withTools.contains { $0.id == .mcpServers || $0.id == .skills }, "No duplicate library pages")
    }
    #endif

    #if !BEFORE
    /// What a pick from either theme menu, Use for Both Modes and Reset to Native write, and their one Undo.
    private static func codeThemeChoices() {
        let defaults = PreviewUserDefaults()
        let selection = CodeThemeSelection(defaults: defaults)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let pick = { (id: String, appearance: CodeAppearance?) in
            undo.beginUndoGrouping()
            selection.select(id, for: appearance, undoManager: undo)
            undo.endUndoGrouping()
        }
        let saved = {
            (
                light: defaults.string(forKey: AppearancePreferences.lightCodeThemeKey) ?? "native",
                dark: defaults.string(forKey: AppearancePreferences.darkCodeThemeKey) ?? "native"
            )
        }
        let ids = CodeTheme.all.map(\.id.rawValue).filter { $0 != CodeTheme.native.id.rawValue }
        guard let first = ids.first, let second = ids.dropFirst().first else {
            return expect(false, "Two built-in code themes to choose between")
        }
        pick(first, .dark)
        expect(saved() == ("native", first), "A dark menu pick keeps the light theme")
        pick(second, nil)
        expect(saved() == (second, second), "Use for Both Modes writes both themes")
        expect(undo.undoActionName == "Code Theme", "Theme changes are named for Undo")
        undo.undo()
        expect(saved() == ("native", first), "One Undo restores both modes")
        undo.redo()
        expect(saved() == (second, second), "Redo reapplies both modes")
        undo.removeAllActions()
        // Outside a group on purpose: registering an Undo step here would raise.
        selection.select(second, for: nil, undoManager: undo)
        expect(!undo.canUndo, "Choosing the current theme adds no Undo step")
        pick("native", nil)
        expect(saved() == ("native", "native"), "Reset to Native resets both modes")
    }

    /// Try On writes nothing while trying or on Cancel, writes both modes and the backgrounds on Keep
    /// as one Undo, returns to Settings, and stays shut while policy sets the code theme.
    private static func soundChoices() async {
        let choices: [Bool?] = [nil, false, true]
        for legacy in choices {
            for plugin in choices {
                let defaults = PreviewUserDefaults()
                defaults.set(legacy, forKey: "sounds.enabled")
                if let plugin { defaults.set([SoundsPlugin.id: plugin], forKey: "pluginChoices") }
                let preferences = SoundPreferences(defaults: defaults)
                let sounds = NotificationSounds(preferences: preferences)
                let registry = PluginRegistry(builtIns: [SoundsPlugin(sounds: sounds)], defaults: defaults)
                SoundsPlugin.connect(sounds, plugins: registry)
                let expected = (legacy ?? true) && (plugin ?? true)
                expect(registry.isEnabled(SoundsPlugin.id) == expected, "Preserve either saved mute")
                expect(sounds.isEnabled() == expected, "Playback follows the migrated plugin choice")
                expect(defaults.object(forKey: "sounds.enabled") == nil, "Remove the legacy switch")
                registry.setEnabled(false, for: SoundsPlugin.id)
                expect(!sounds.isEnabled(), "Disabling the plugin takes effect immediately")
                expect(await sounds.play(.taskFinished) == false, "Disabled playback is silent")
                registry.setEnabled(true, for: SoundsPlugin.id)
                expect(sounds.isEnabled(), "Enabling the plugin takes effect immediately")
                SoundsPlugin.connect(sounds, plugins: registry)
                expect(sounds.isEnabled(), "Migration runs only once")
                let reopened = PluginRegistry(builtIns: [SoundsPlugin(sounds: sounds)], defaults: defaults)
                expect(reopened.isEnabled(SoundsPlugin.id), "The chosen state survives reopening")
            }
        }
    }
    #endif
}
