import SwiftUI

/// What a feature shows before a task's own transcript, above its first row: the conversation the
/// task continues from, say.
struct TranscriptPrelude {
    let content: AnyView
}

extension EnvironmentValues {
    @Entry var transcriptPrelude: TranscriptPrelude?
}
