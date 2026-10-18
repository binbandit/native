import Foundation

/// A playable sound as the picker lists it.
nonisolated struct SoundOption: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case synthesized(NativeChime)
        /// Played in place: the user's files are never copied.
        case file(URL)
    }

    let id: SoundID
    let title: String
    let source: Source
}
