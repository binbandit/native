import CodeThemes
import Experiments
import Foundation
import NativeHostProtocol
import NativePolicy
import Skills

@testable import Native

@MainActor
private final class InertKeepAwakeEngine: KeepAwakeEngine {
    var onChange: ((KeepAwakeStatus) -> Void)?
    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus { .off }
    func stop() {}
}

@main
@MainActor
private struct SettingsRegression {
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
        plainlyNavigation()
        combinedLibraryScope()
        accountNavigation()
        codeThemeChoices()
        themeTryOn()
        #endif
        if failures > 0 {
            print("FAILED: \(failures) Settings regressions")
            exit(1)
        }
        print(
            "PASS: Settings navigation, account links, code theme choices, Try On, sound migration, live switching and disabled playback"
        )
    }

    private static func expect(_ condition: Bool, _ message: String) {
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
    private static func themeTryOn() {
        let defaults = PreviewUserDefaults()
        let settings = SettingsPresentation()
        var policy = NativePolicy()
        let tryOn = ThemeTryOnModel(
            app: AppModel.preview(.empty), settings: settings,
            appearance: AppearanceModeController(defaults: PreviewUserDefaults()),
            plugins: PluginRegistry(previewing: []), defaults: defaults, policy: { policy })
        let saved = {
            [
                AppearancePreferences.lightCodeThemeKey, AppearancePreferences.darkCodeThemeKey,
                AppearancePreferences.lightToneKey, AppearancePreferences.darkToneKey,
            ].map { defaults.string(forKey: $0) ?? "-" }
        }
        let untouched = saved()
        settings.open(.appearance)
        tryOn.start()
        expect(tryOn.stage == .sample && !settings.isShown, "Try On without tasks opens the sample over Settings")
        expect(tryOn.trial?.highlighted == .native, "The list starts on the theme in use")
        tryOn.show(.dark)
        tryOn.highlight(CodeTheme.nord.id)
        tryOn.move(1)
        tryOn.move(-1)
        tryOn.setBackgrounds(.init(light: .wool, dark: .trueBlack))
        expect(tryOn.trial?.highlighted == .nord, "Arrows move the highlight and back")
        expect(saved() == untouched, "Trying writes nothing")
        tryOn.cancel()
        expect(saved() == untouched && !tryOn.isActive, "Cancel writes nothing")
        expect(settings.pane == .appearance && tryOn.keptNote == nil, "Cancel returns to Appearance")

        let undo = UndoManager()
        undo.groupsByEvent = false
        tryOn.start()
        tryOn.show(.dark)
        _ = tryOn.highlight(matching: "to")
        tryOn.show(.light)
        tryOn.highlight(CodeTheme.github.id)
        tryOn.setBackgrounds(.init(light: .wool, dark: .standard))
        undo.beginUndoGrouping()
        tryOn.keep(undoManager: undo)
        undo.endUndoGrouping()
        let kept = ["github", "tokyo-night", "wool", "standard"]
        expect(saved() == kept, "Keep writes both modes and the backgrounds: \(saved())")
        expect(settings.pane == .appearance && !tryOn.isActive, "Keep returns to Appearance")
        expect(
            tryOn.keptNote?.message
                == "Kept GitHub for light mode and Tokyo Night for dark mode. The terminal uses them too.",
            "The kept line names what changed, the listed mode first")
        expect(undo.undoActionName == "Code Theme", "Keep is named for Undo")
        undo.undo()
        expect(saved() == ["native", "native", "paper", "standard"], "Undo restores what was there")
        expect(tryOn.keptNote == nil, "Undo takes the kept line away")
        undo.redo()
        expect(saved() == kept, "Redo keeps them again")

        undo.removeAllActions()
        tryOn.start()
        tryOn.show(.dark)
        tryOn.highlight(CodeTheme.nord.id)
        undo.beginUndoGrouping()
        tryOn.keep(undoManager: undo)
        undo.endUndoGrouping()
        tryOn.undoKeep(undoManager: undo)
        expect(saved() == kept && !undo.canUndo, "The kept line's Undo restores and leaves nothing to undo twice")

        tryOn.start()
        tryOn.highlight(CodeTheme.dracula.id)
        tryOn.abandon()
        expect(saved() == kept && !tryOn.isActive, "Leaving for another task writes nothing")

        policy = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.appearance.codeTheme": "native"]))
        tryOn.start()
        expect(!tryOn.isAvailable && !tryOn.isActive, "Try On stays shut while policy sets the code theme")
    }

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
