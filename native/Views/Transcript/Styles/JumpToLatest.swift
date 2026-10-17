import ACP
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
        Button("Jump to Latest") { jump?.action() }
            .disabled(jump == nil)
    }
}

/// Scrolls a session's transcript to its newest output. Equal for the same session, so the focused
/// value doesn't change, and menus don't update, on every transcript update.
struct TranscriptJumpCommand: Equatable {
    let sessionID: SessionID
    let action: @MainActor () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionID == rhs.sessionID
    }
}

extension FocusedValues {
    /// Jumps the visible session's transcript to its newest output, while it's scrolled away.
    @Entry var transcriptJumpToLatest: TranscriptJumpCommand?
}

extension EnvironmentValues {
    /// Whether this transcript is the session's own (not a subagent's in the inspector), so it's
    /// the one menu commands act on.
    @Entry var isPrimaryTranscript = false
}
