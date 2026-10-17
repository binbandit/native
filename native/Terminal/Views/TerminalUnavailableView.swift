import SwiftUI

/// What the panel shows in a build without libghostty: what's missing and the one step that
/// fixes it.
struct TerminalUnavailableView: View {
    @State private var didCopy = false

    var body: some View {
        EmptyStateView(
            "Terminal isn't available in this build",
            systemImage: "apple.terminal",
            message: "This copy of Native was built without libghostty, Ghostty's terminal library. "
                + "Run \(TerminalAvailability.buildCommand) in the Native repository once, then build Native again."
        ) {
            Button(didCopy ? "Copied" : "Copy Command") {
                DSPasteboard.copy(TerminalAvailability.buildCommand)
                didCopy = true
            }
        }
    }
}

#Preview("Terminal unavailable") {
    DSPreviewPair {
        TerminalUnavailableView()
            .frame(width: 560, height: 220)
            .background(.dsSurfaceSunken)
    }
}
