import SwiftUI

/// The Bubbles experiment's transcript. Work in progress: shows the standard rows for now.
struct BubbleTranscriptStyle: TranscriptStyle {
    func makeBody(_ transcript: TranscriptStyleConfiguration) -> some View {
        StandardTranscriptStyle().makeBody(transcript)
    }
}
