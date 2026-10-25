import SwiftUI

/// What a feature adds after a task's own transcript, below its last row: a card about the task as
/// a whole rather than any one turn (the two versions of a brief, say). When it speaks for the
/// task's changes, the latest turn's files-changed card steps aside so they aren't counted twice.
struct TranscriptTrailer {
    let content: AnyView
    var replacesChangesCard = false
}

extension EnvironmentValues {
    @Entry var transcriptTrailer: TranscriptTrailer?
}
