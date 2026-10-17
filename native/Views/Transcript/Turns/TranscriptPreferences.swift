import SwiftUI

/// The user's transcript settings, kept in the app's defaults.
enum TranscriptPreferences {
    /// Whether earlier turns fold their tool work into one line (View ▸ Fold Earlier Turns). On by
    /// default; the latest turn always shows every row.
    static let foldsEarlierTurnsKey = "transcript.foldsEarlierTurns"
}

/// View ▸ Fold Earlier Turns: a checkmark item for the menu bar.
struct FoldEarlierTurnsToggle: View {
    @AppStorage(TranscriptPreferences.foldsEarlierTurnsKey) private var foldsEarlierTurns = true

    var body: some View {
        Toggle("Fold Earlier Turns", isOn: $foldsEarlierTurns)
    }
}
