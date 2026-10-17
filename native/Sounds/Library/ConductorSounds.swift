import Foundation

/// Conductor's notification sounds, offered when the user has a local copy of Conductor's frontend
/// files. They're Conductor's to distribute, not ours, so Native never bundles or copies them: it
/// lists the ones present and plays them from where they are.
nonisolated enum ConductorSounds {
    /// Where the user keeps an extracted copy of Conductor's frontend.
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "developer/reverse/conductor/extracted/frontend", directoryHint: .isDirectory)

    /// Conductor's picker, in its order and with its labels and groups (`sound_type` in its
    /// settings).
    private static let catalog: [(group: String, sounds: [(id: String, title: String, file: String)])] = [
        ("Classic", [
            ("default", "Chime", "chime.mp3"),
            ("choo-choo", "Choo Choo", "choo-choo.mp3"),
        ]),
        ("Novelty", [
            ("odysseus-pluck", "Odysseus's Pluck", "odysseus-pluck.mp3"),
            ("fahhhh", "Fahhhh", "fahhhh.mp3"),
            ("quack", "Quack", "quack.mp3"),
        ]),
        ("SF Muni", [
            ("sf-muni-inbound-train-chime", "Inbound Train", "sf-muni-inbound-train-chime.mp3"),
            ("sf-muni-new", "Gong", "sf-muni-gong.mp3"),
        ]),
        ("NYC MTA", [
            ("nyc-metro-door-chime", "Chime 1", "nyc-metro-door-chime.mp3"),
            ("nyc-subway-door-chime", "Chime 2", "nyc-subway-door-chime.mp3"),
            ("nyc-subway", "Stand Clear", "nyc-subway.mp3"),
        ]),
        ("Paris Métro", [
            ("paris-metro-chime", "Chime", "paris-metro-chime.mp3"),
            ("paris-metro-pickpockets", "Attention aux pickpockets", "paris-metro-pickpockets.mp3"),
        ]),
        ("SNCF", [
            ("sncf-jingle", "Jingle", "sncf-jingle.mp3"),
        ]),
    ]

    /// The groups whose files exist in `folder`; empty without a local copy.
    static func discover(in folder: URL = folder) -> [SoundGroup] {
        catalog.compactMap { group in
            let options = group.sounds.compactMap { sound -> SoundOption? in
                let url = folder.appending(path: sound.file)
                guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else { return nil }
                return SoundOption(id: .conductor(sound.id), title: sound.title, source: .file(url))
            }
            return options.isEmpty ? nil : SoundGroup(title: group.group, options: options)
        }
    }
}
