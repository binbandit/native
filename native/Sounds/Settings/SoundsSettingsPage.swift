import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sounds, in the reference app's row style: the sound with a Test button, its volume, the
/// moments that play it and when.
struct SoundsSettingsPage: View {
    static let soundRow = SettingsRowID("sounds.sound")
    static let volumeRow = SettingsRowID("sounds.volume")
    static let timingRow = SettingsRowID("sounds.timing")
    static func triggerRow(_ trigger: SoundTrigger) -> SettingsRowID {
        SettingsRowID("sounds.trigger.\(trigger.rawValue)")
    }

    /// the reference app's sound select (`w-[190px]`), wider than its other selects for the longer names.
    static let selectWidth: CGFloat = 190

    let sounds: NotificationSounds

    @State private var isAddingSound = false

    private var preferences: SoundPreferences {
        sounds.preferences
    }

    private var isSilent: Bool {
        preferences.selection == .none
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsHeader("Sounds", description: Text("Hear when an agent finishes or needs you, without watching it work."))
            SettingsRowGroup {
                SettingsRow(
                    id: Self.soundRow,
                    "Notification sound",
                    description: Text("Choose what plays when a task finishes or needs you."),
                    detail: sounds.catalog.conductor.isEmpty ? nil : Text("the reference app's sounds play from your copy in \((ConductorSounds.folder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath).")
                ) {
                    HStack(spacing: DS.Space.md) {
                        SoundPicker(sounds: sounds) { isAddingSound = true }
                        Button("Test", systemImage: "speaker.wave.2") {
                            sounds.preview()
                        }
                        .buttonStyle(.ds(.ghost, size: .medium))
                        .disabled(isSilent)
                    }
                }
                SettingsRow(id: Self.volumeRow, "Volume", description: Text("How loud notification sounds play.")) {
                    VolumeSlider(volume: $preferences.volume) {
                        sounds.preview()
                    }
                    .frame(width: Self.selectWidth)
                }
                SettingsRow(id: Self.timingRow, "When to play", description: Text("Stay quiet for the task you're looking at, or whenever Native is in front.")) {
                    SettingsSelect(
                        label: "When to play",
                        selection: $preferences.timing,
                        options: SoundTiming.allCases.map { .init(value: $0, title: $0.title) },
                        width: Self.selectWidth
                    )
                }
            }
            .disabled(isSilent)

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
            .disabled(isSilent)
        }
        .fileImporter(isPresented: $isAddingSound, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                sounds.addSounds(at: urls)
            }
        }
        // the reference app's folder or a custom file may have moved since the page was last open.
        .onAppear { sounds.reloadCatalog() }
    }
}
