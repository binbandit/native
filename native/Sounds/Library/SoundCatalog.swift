import Foundation

/// Every sound the user can pick, in the groups the picker shows.
nonisolated struct SoundCatalog: Sendable {
    let native: [SoundOption]
    /// The user's sounds folder as last listed; nil when they haven't chosen one.
    let folder: SoundsFolderListing?
    let custom: [SoundOption]

    init(customSounds: [CustomSound], folder: SoundsFolder?) {
        native = NativeChime.allCases.map { SoundOption(id: .native($0), title: $0.title, source: .synthesized($0)) }
        self.folder = folder?.listing()
        custom = customSounds.compactMap(\.option)
    }

    /// The option for `id`; nil for files that have gone missing.
    func option(for id: SoundID) -> SoundOption? {
        switch id {
        case .native(let chime): native.first { $0.id == .native(chime) }
        case .folder: folder?.sounds.first { $0.id == id }
        case .custom: custom.first { $0.id == id }
        }
    }
}
