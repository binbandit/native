import Foundation

/// A request to scroll a transcript to one item and highlight it, as when search opens a task at
/// the message it found. The transcript clears it once it has scrolled.
struct TranscriptReveal: Equatable {
    let id = UUID()
    /// The `TranscriptItem.id` to show.
    let itemID: String
}
