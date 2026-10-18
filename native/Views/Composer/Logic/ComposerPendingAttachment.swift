import Foundation

/// A file or image still being read (a large photo takes a moment to scale), shown as a chip in
/// its place until it's attached. Sending waits for it.
struct ComposerPendingAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
}
