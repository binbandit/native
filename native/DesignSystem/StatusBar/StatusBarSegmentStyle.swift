import SwiftUI

/// A clickable status-bar item: no box, just its text brightening from tertiary to primary
/// under the pointer, as the sidebar footer's glyphs do, and dimming while pressed. The one
/// exception is `.attention`, for something blocked on the user: it alone gets a soft capsule in
/// the attention color, so it's the first thing the eye finds in the bar.
public struct StatusBarSegmentStyle: ButtonStyle {
    public enum Tone: Sendable {
        case standard
        /// Blocked on the user: tasks that need an answer. Use it for one item at most.
        case attention
    }

    let tone: Tone
    /// Its popover or menu is open.
    let isActive: Bool

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(StatusBarSegmentChrome(tone: tone, isActive: isActive, isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == StatusBarSegmentStyle {
    /// A status-bar item that opens something: a popover, a menu, a task.
    public static func statusBarSegment(_ tone: StatusBarSegmentStyle.Tone = .standard, isActive: Bool = false) -> Self
    {
        StatusBarSegmentStyle(tone: tone, isActive: isActive)
    }
}

extension View {
    /// The status-bar item look for a label the style can't reach, such as a `Menu`'s. Prefer
    /// `.buttonStyle(.statusBarSegment())`, which also shows the pressed state.
    public func statusBarSegment(_ tone: StatusBarSegmentStyle.Tone = .standard, isActive: Bool = false) -> some View {
        modifier(StatusBarSegmentChrome(tone: tone, isActive: isActive, isPressed: false))
    }
}

private struct StatusBarSegmentChrome: ViewModifier {
    let tone: StatusBarSegmentStyle.Tone
    let isActive: Bool
    let isPressed: Bool

    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = Capsule()
        content
            .font(.dsCaption)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, tone == .attention ? DS.Space.sm : 0)
            .padding(.vertical, DS.Space.xxs)
            .background {
                if tone == .attention {
                    shape.fill(.dsAttention.opacity(washOpacity))
                }
            }
            // The full height of the bar, and a little past the text's ends, is the target.
            .frame(maxHeight: .infinity)
            .contentShape(.rect.inset(by: -DS.Space.xs))
            .dsFocusShape(shape)
            .trackHover($isHovered)
            .animation(.dsQuick, value: isPressed)
    }

    private var foreground: Color {
        switch tone {
        case .standard:
            if isPressed { .dsTextSecondary } else if isHovered || isActive { .dsTextPrimary } else { .dsTextTertiary }
        case .attention:
            .dsAttention
        }
    }

    private var washOpacity: Double {
        if isPressed { 0.24 } else if isHovered || isActive { 0.18 } else { 0.12 }
    }
}
