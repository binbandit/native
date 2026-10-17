import SwiftUI

/// The small round button that floats above the composer while a turn runs and you've scrolled
/// up, and takes you back to the newest output.
struct JumpToLatestButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.dsCalloutMedium)
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Jump to the latest output")
        .accessibilityLabel("Jump to latest")
    }
}

/// View ▸ Jump to Latest, for the session transcript on screen.
struct JumpToLatestMenuItem: View {
    @FocusedValue(\.transcriptJumpToLatest) private var jump

    var body: some View {
        Button("Jump to Latest") { jump?() }
            .disabled(jump == nil)
    }
}

extension FocusedValues {
    /// Scrolls the visible session's transcript to its newest output.
    @Entry var transcriptJumpToLatest: (@MainActor () -> Void)?
}

extension EnvironmentValues {
    /// Whether this transcript is the session's own (not a subagent's in the inspector), so it's
    /// the one menu commands act on.
    @Entry var isPrimaryTranscript = false
}
