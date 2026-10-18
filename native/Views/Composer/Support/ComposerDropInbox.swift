import Observation
import SwiftUI

/// Files and images dropped beside the composer (on the transcript), handed to it to attach. The
/// session view owns one and marks its drop area with `composerDropTarget(_:)`.
@Observable
final class ComposerDropInbox {
    var items: [ComposerDropItem] = []
    /// Whether a drag is over the area, so the composer can light up as the place it lands.
    var isTargeted = false
}

extension View {
    /// Drops on this view go to the composer inside it, as attachments.
    func composerDropTarget(_ inbox: ComposerDropInbox) -> some View {
        dropDestination(for: ComposerDropItem.self) { items, _ in
            inbox.items += items
            return !items.isEmpty
        } isTargeted: {
            inbox.isTargeted = $0
        }
        .environment(inbox)
    }
}
