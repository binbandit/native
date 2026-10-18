import SwiftUI

/// A status-bar item that shows its details in a popover: a `.statusBarSegment()` button that's
/// keyboard-focusable, lit while its popover is open, and explains itself on hover and to
/// VoiceOver. Items that open a menu instead dress their label with `.statusBarSegment()`.
struct StatusBarSegment<Label: View, Details: View>: View {
    /// What the tooltip and VoiceOver say: what the item measures and its current value.
    let help: String
    let accessibilityLabel: String
    var accessibilityValue = ""
    /// Called as the details open, for fetching fresh numbers.
    var onOpen: () -> Void = {}
    @ViewBuilder var label: Label
    @ViewBuilder var details: Details

    @State private var isPresented = false

    var body: some View {
        Button {
            if !isPresented {
                onOpen()
            }
            isPresented.toggle()
        } label: {
            label
        }
        .buttonStyle(.statusBarSegment(isActive: isPresented))
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows details")
        .dsPopover(isPresented: $isPresented) {
            details
        }
    }
}
