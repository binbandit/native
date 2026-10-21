import SwiftUI

/// What a tool says about the task under the title: data, never a label ("2 files", "Dev :3000",
/// "Cursor"), with what it needs beside it.
struct SessionToolFact {
    enum Accessory {
        /// Lines added and removed, as the diff stat everywhere else.
        case diff(added: Int, removed: Int)
        /// Something is running.
        case working
        /// The last run failed.
        case failed
        /// An app's own icon (Open In's editor).
        case icon(Image)
    }

    var text: String
    var accessory: Accessory?
}
