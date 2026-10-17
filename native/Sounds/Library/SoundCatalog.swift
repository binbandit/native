import Foundation

/// Every sound the user can pick, in the groups the picker shows.
nonisolated struct SoundCatalog: Sendable {
    let native: [SoundOption]
    /// the reference app's sounds from the user's local copy, by the reference app's own groups.
    let conductor: [SoundGroup]
    let custom: [SoundOption]

    init(customSounds: [CustomSound], conductorFolder: URL = ConductorSounds.folder) {
        native = NativeChime.allCases.map { SoundOption(id: .native($0), title: $0.title, source: .synthesized($0)) }
        conductor = ConductorSounds.discover(in: conductorFolder)
        custom = customSounds.compactMap(\.option)
    }

    /// The option for `id`; nil for `.none` and for files that have gone missing.
    func option(for id: SoundID) -> SoundOption? {
        switch id {
        case .none: nil
        case .native(let chime): native.first { $0.id == .native(chime) }
        case .conductor: conductor.lazy.flatMap(\.options).first { $0.id == id }
        case .custom: custom.first { $0.id == id }
        }
    }
}
