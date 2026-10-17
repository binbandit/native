import Foundation

/// A playable sound as the picker lists it.
nonisolated struct SoundOption: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case synthesized(NativeChime)
        /// Played in place: the reference app's and the user's files are never copied.
        case file(URL)
    }

    let id: SoundID
    let title: String
    let source: Source
}

/// Sounds listed under one heading.
nonisolated struct SoundGroup: Identifiable, Hashable, Sendable {
    let title: String
    let options: [SoundOption]

    var id: String { title }
}
