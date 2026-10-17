import SwiftUI

/// A status-bar segment that shows its details in a popover: the reference app's trigger (11pt medium
/// tabular figures in the secondary color, 12pt glyphs, a 4pt-rounded hover wash) on a button
/// that's keyboard-focusable and explains itself on hover and to VoiceOver.
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
            label.statusBarSegmentChrome(isActive: isPresented)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows details")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            details
        }
    }
}

extension View {
    /// Dresses a segment's content: for segments that open a menu instead of a popover.
    func statusBarSegmentChrome(isActive: Bool = false) -> some View {
        modifier(StatusBarSegmentChrome(isActive: isActive))
    }
}

private struct StatusBarSegmentChrome: ViewModifier {
    let isActive: Bool

    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        content
            .font(.dsCaptionMedium)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(isHovered || isActive ? .dsTextPrimary : .dsTextSecondary)
            .padding(StatusBarMetrics.segmentPadding)
            .background(isActive ? Color.dsSelected : isHovered ? .dsHover : .clear, in: shape)
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
            .trackHover($isHovered)
    }
}

/// A segment's glyph at the reference app's 12px.
struct StatusBarGlyph: View {
    let systemName: String

    init(_ systemName: String) {
        self.systemName = systemName
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: StatusBarMetrics.glyph, weight: .medium))
            .accessibilityHidden(true)
    }
}

/// The faint dot between two figures in a segment ("745.7 MB · 2").
struct StatusBarDivider: View {
    var body: some View {
        Text("·")
            .foregroundStyle(.dsTextQuaternary)
            .accessibilityHidden(true)
    }
}
