import SwiftUI

/// The Bubbles experiment's transcript. Work in progress: shows the standard rows for now.
nonisolated struct BubbleTranscriptStyle: TranscriptStyle {
    @MainActor func makeBody(_ transcript: TranscriptStyleConfiguration) -> some View {
        StandardTranscriptStyle().makeBody(transcript)
    }
}
