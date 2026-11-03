import ACP
import SwiftUI

/// What a feature shows with a context marker (`PromptPreamble`) in a task's transcript, above its
/// line: what the other agents did that the context came from, say. Nil shows the marker alone.
struct TranscriptMarkerContext {
    let content: (PromptPreamble.Marker) -> AnyView?
}

extension EnvironmentValues {
    @Entry var transcriptMarkerContext: TranscriptMarkerContext?
}
