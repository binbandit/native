import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sounds: one switch for all sounds, their volume, Focus, timing and the folder of the
/// user's own sounds, then each moment with its own sound, a Test button and a switch.
struct SoundsSettingsPage: View {
    static let enabledRow = SettingsRowID("sounds.enabled")
    static let volumeRow = SettingsRowID("sounds.volume")
    static let focusRow = SettingsRowID("sounds.focus")
    static let timingRow = SettingsRowID("sounds.timing")
    static let folderRow = SettingsRowID("sounds.folder")
    static func triggerRow(_ trigger: SoundTrigger) -> SettingsRowID {
        SettingsRowID("sounds.trigger.\(trigger.rawValue)")
    }

    /// The sound selects, wider than other settings selects for the longer names.
    static let selectWidth: CGFloat = 190

    let sounds: NotificationSounds

    @Environment(PluginRegistry.self) private var plugins

    /// The trigger a picked file goes to, while the file picker is open.
    @State private var addingSoundFor: SoundTrigger?

    private var preferences: SoundPreferences {
        sounds.preferences
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsHeader(
                "Sounds",
                description: Text(
                    "Hear when an agent finishes, needs you, or runs into trouble, without watching it work."))
            SettingsRowGroup {
                SettingsRow(
                    id: Self.enabledRow, "Play sounds",
                    description: Text("Turn off to silence every sound Native plays.")
                ) {
                    SettingsSwitch(
                        "Play sounds",
                        isOn: Binding(
                            get: { plugins.isEnabled(SoundsPlugin.id) },
                            set: { plugins.setEnabled($0, for: SoundsPlugin.id) }
                        )
                    )
                }
                SettingsRow(id: Self.volumeRow, "Volume", description: Text("How loud Native's sounds play.")) {
                    VolumeSlider(volume: $preferences.volume) {
                        sounds.preview(.taskFinished)
                    }
                    .frame(width: Self.selectWidth)
                }
                .disabled(!plugins.isEnabled(SoundsPlugin.id))
                SettingsRow(
                    id: Self.focusRow,
                    "Stay quiet during Focus",
                    description: Text(
                        "When off, Native plays sounds even while Do Not Disturb or another Focus is on."),
                    detail: focusNote
                ) {
                    SettingsSwitch(
                        "Stay quiet during Focus",
                        isOn: Binding {
                            preferences.staysQuietDuringFocus
                        } set: {
                            sounds.setStaysQuietDuringFocus($0)
                        })
                }
                .disabled(!plugins.isEnabled(SoundsPlugin.id))
                SettingsRow(
                    id: Self.timingRow, "When to play",
                    description: Text("Stay quiet for the task you're looking at, or whenever Native is in front.")
                ) {
                    SettingsSelect(
                        label: "When to play",
                        selection: $preferences.timing,
                        options: SoundTiming.allCases.map { .init(value: $0, title: $0.title) },
                        width: Self.selectWidth
                    )
                }
                .disabled(!plugins.isEnabled(SoundsPlugin.id))
                SoundsFolderRow(sounds: sounds)
                    .disabled(!plugins.isEnabled(SoundsPlugin.id))
            }

            SettingsSubheading("Play a sound when")
            SettingsRowGroup {
                ForEach(SoundTrigger.allCases) { trigger in
                    SettingsRow(id: Self.triggerRow(trigger), trigger.title, description: Text(trigger.detail)) {
                        triggerControls(trigger)
                    }
                }
            }
            .disabled(!plugins.isEnabled(SoundsPlugin.id))
        }
        .fileImporter(
            isPresented: Binding {
                addingSoundFor != nil
            } set: {
                if !$0 { addingSoundFor = nil }
            },
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result, let trigger = addingSoundFor {
                sounds.addSounds(at: urls, for: trigger)
            }
        }
        // The sounds folder's files or a custom file may have changed since the page was last open.
        .onAppear { sounds.reloadCatalog() }
    }

    /// The trigger's sound, a Test button, and its switch; the sound dims while it's off.
    private func triggerControls(_ trigger: SoundTrigger) -> some View {
        let isOn = preferences.isEnabled(trigger)
        return HStack(spacing: DS.Space.md) {
            SoundPicker(sounds: sounds, trigger: trigger) { addingSoundFor = trigger }
                .disabled(!isOn)
            IconButton("Test \(trigger.title.lowercased()) sound", systemImage: "speaker.wave.2", size: .large) {
                sounds.preview(trigger)
            }
            .disabled(!isOn)
            SettingsSwitch(
                trigger.title,
                isOn: Binding {
                    preferences.isEnabled(trigger)
                } set: {
                    preferences.setEnabled($0, for: trigger)
                })
        }
    }

    /// When Native can't see Focus, says so and what that means, instead of quietly not working.
    private var focusNote: Text? {
        guard preferences.staysQuietDuringFocus else { return nil }
        switch sounds.focus.access {
        case .allowed, .notDetermined:
            return nil
        case .denied:
            return Text(
                "Native can't see your Focus status, so sounds still play during Focus. Allow it in System Settings ▸ Privacy & Security ▸ Focus."
            )
        case .unavailable:
            return Text("This build of Native can't see your Focus status, so sounds still play during Focus.")
        }
    }
}

#if DEBUG
#Preview("Sounds settings - On") {
    let defaults = PreviewUserDefaults()
    let sounds = NotificationSounds(preferences: SoundPreferences(defaults: defaults))
    DSPreviewPair {
        SoundsSettingsPage(sounds: sounds)
            .settingsPreviewPage()
            .environment(PluginRegistry(builtIns: [SoundsPlugin(sounds: sounds)], defaults: defaults))
    }
}

#Preview("Sounds settings - Off") {
    let defaults = PreviewUserDefaults()
    let sounds = NotificationSounds(preferences: SoundPreferences(defaults: defaults))
    let registry = PluginRegistry(builtIns: [SoundsPlugin(sounds: sounds)], defaults: defaults)
    let _ = registry.setEnabled(false, for: SoundsPlugin.id)
    DSPreviewPair {
        SoundsSettingsPage(sounds: sounds)
            .settingsPreviewPage()
            .environment(registry)
    }
}
#endif
