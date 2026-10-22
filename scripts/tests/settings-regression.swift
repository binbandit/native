import Foundation
import NativeHostProtocol

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
        if failures > 0 {
            print("FAILED: \(failures) Settings regressions")
            exit(1)
        }
        print("PASS: Settings order, sound migration, live switching and disabled playback")
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
