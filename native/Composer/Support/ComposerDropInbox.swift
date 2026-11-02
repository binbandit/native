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
    /// Drops on this view go to the composer inside it, as attachments. Refused while `isEnabled` is
    /// off, when there's no composer to take them.
    func composerDropTarget(_ inbox: ComposerDropInbox, isEnabled: Bool = true) -> some View {
        composerAttachmentDrop(isEnabled: isEnabled, isTargeted: { inbox.isTargeted = isEnabled && $0 }) { items in
            inbox.items += items
        }
        .environment(inbox)
    }
}
