import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sounds, in Conductor's row style: one switch for all sounds, the sound with a Test
/// button, its volume, Focus, the moments that play it and when.
struct SoundsSettingsPage: View {
    static let enabledRow = SettingsRowID("sounds.enabled")
    static let soundRow = SettingsRowID("sounds.sound")
    static let volumeRow = SettingsRowID("sounds.volume")
    static let focusRow = SettingsRowID("sounds.focus")
    static let timingRow = SettingsRowID("sounds.timing")
    static func triggerRow(_ trigger: SoundTrigger) -> SettingsRowID {
        SettingsRowID("sounds.trigger.\(trigger.rawValue)")
    }

    /// Conductor's sound select (`w-[190px]`), wider than its other selects for the longer names.
    static let selectWidth: CGFloat = 190

    let sounds: NotificationSounds

    @State private var isAddingSound = false

    private var preferences: SoundPreferences {
        sounds.preferences
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsHeader("Sounds", description: Text("Hear when an agent finishes or needs you, without watching it work."))
            SettingsRowGroup {
                SettingsRow(id: Self.enabledRow, "Play sounds", description: Text("Turn off to silence every sound Native plays.")) {
                    SettingsSwitch("Play sounds", isOn: $preferences.isEnabled)
                }
                SettingsRow(
                    id: Self.soundRow,
                    "Notification sound",
                    description: Text("Choose what plays when a task finishes or needs you."),
                    detail: sounds.catalog.conductor.isEmpty ? nil : Text("Conductor's sounds play from your copy in \((ConductorSounds.folder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath).")
                ) {
                    HStack(spacing: DS.Space.md) {
                        SoundPicker(sounds: sounds) { isAddingSound = true }
                        Button("Test", systemImage: "speaker.wave.2") {
                            sounds.preview()
                        }
                        .buttonStyle(.ds(.ghost, size: .medium))
                    }
                }
                .disabled(!preferences.isEnabled)
                SettingsRow(id: Self.volumeRow, "Volume", description: Text("How loud notification sounds play.")) {
                    VolumeSlider(volume: $preferences.volume) {
                        sounds.preview()
                    }
                    .frame(width: Self.selectWidth)
                }
                .disabled(!preferences.isEnabled)
                SettingsRow(
                    id: Self.focusRow,
                    "Stay quiet during Focus",
                    description: Text("When off, Native plays sounds even while Do Not Disturb or another Focus is on."),
                    detail: focusNote
                ) {
                    SettingsSwitch("Stay quiet during Focus", isOn: Binding {
                        preferences.staysQuietDuringFocus
                    } set: {
                        sounds.setStaysQuietDuringFocus($0)
                    })
                }
                .disabled(!preferences.isEnabled)
                SettingsRow(id: Self.timingRow, "When to play", description: Text("Stay quiet for the task you're looking at, or whenever Native is in front.")) {
                    SettingsSelect(
                        label: "When to play",
                        selection: $preferences.timing,
                        options: SoundTiming.allCases.map { .init(value: $0, title: $0.title) },
                        width: Self.selectWidth
                    )
                }
                .disabled(!preferences.isEnabled)
            }

            SettingsSubheading("Play a sound when")
            SettingsRowGroup {
                ForEach(SoundTrigger.allCases) { trigger in
                    SettingsRow(id: Self.triggerRow(trigger), trigger.title, description: Text(trigger.detail)) {
                        SettingsSwitch(trigger.title, isOn: Binding {
                            preferences.isEnabled(trigger)
                        } set: {
                            preferences.setEnabled($0, for: trigger)
                        })
                    }
                }
            }
            .disabled(!preferences.isEnabled)
        }
        .fileImporter(isPresented: $isAddingSound, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                sounds.addSounds(at: urls)
            }
        }
        // Conductor's folder or a custom file may have moved since the page was last open.
        .onAppear { sounds.reloadCatalog() }
    }

    /// When Native can't see Focus, says so and what that means, instead of quietly not working.
    private var focusNote: Text? {
        guard preferences.staysQuietDuringFocus else { return nil }
        switch sounds.focus.access {
        case .allowed, .notDetermined:
            return nil
        case .denied:
            return Text("Native can't see your Focus status, so sounds still play during Focus. Allow it in System Settings ▸ Privacy & Security ▸ Focus.")
        case .unavailable:
            return Text("This build of Native can't see your Focus status, so sounds still play during Focus.")
        }
    }
}
