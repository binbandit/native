import SwiftUI

/// The design system's namespace for metrics: spacing, radii, sizes and shadows. Colors, fonts and
/// animations live on their SwiftUI types with a `ds` prefix (`.dsTextSecondary`, `.dsBody`,
/// `.dsQuick`) so leading-dot syntax works.
public nonisolated enum DS {
    /// the reference app's spacing scale (`--core-v2-space-*`, px = pt).
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    public enum Radius {
        /// Keyboard hints, tooltips, progress bars (the reference app `--core-v2-radius-control`, 2px).
        public static let small: CGFloat = 2
        /// Buttons, the composer and its pills, the update button (the reference app `--radius-sm`, 4px).
        public static let control: CGFloat = 4
        /// Sidebar rows: nav items, projects, tasks (the reference app `rounded-md`, 6px).
        public static let row: CGFloat = 6
        /// Cards and popovers (the reference app `rounded-lg`, 8px).
        public static let card: CGFloat = 8
        /// Large panels and sheets (the reference app `rounded-xl`, 12px).
        public static let panel: CGFloat = 12
    }

    public enum Size {
        /// the reference app control heights (`--core-v2-control-height-*`).
        public static let controlXS: CGFloat = 24
        public static let controlSM: CGFloat = 28
        public static let controlMD: CGFloat = 32
        /// Square window-toolbar buttons: the sidebar toggle, back and forward (the reference app 24px).
        public static let toolbarButton: CGFloat = 24
        /// Glyph size of sidebar nav icons (the reference app `icon-size-sm`, 12px).
        public static let navIcon: CGFloat = 12
        /// The leading slot of project and task rows (the reference app `size-4`).
        public static let rowLeading: CGFloat = 16
        /// The status glyph inside that slot (the reference app `size-3.5`).
        public static let statusGlyph: CGFloat = 14
        /// The composer's send and stop buttons (the reference app 24px).
        public static let composerAction: CGFloat = 24
        /// The composer's pills and square buttons (the reference app 28px).
        public static let composerPill: CGFloat = 28
        /// Minimum height of the composer's text section (the reference app 43px).
        public static let composerInputMinHeight: CGFloat = 43
        /// Rows in compact lists and popups: slash commands, queued messages, suggestions
        /// (the reference app `SuggestionRow`, 26px).
        public static let listRow: CGFloat = 26
        /// The readable column of the transcript, the composer and other long-form content: wide
        /// enough for code, narrow enough to read.
        public static let contentColumn: CGFloat = 760
        /// Default sidebar width (the reference app 256px; the reference app ~260px).
        public static let sidebarWidth: CGFloat = 256
        /// The window's bottom chrome strips: the status bar, and the sidebar footer above it while
        /// the bar is shown, so the two stack evenly. A full touch target on iPadOS.
        #if os(iOS)
        public static let chromeBar: CGFloat = 44
        #else
        public static let chromeBar: CGFloat = 32
        #endif
        /// Popover panels that hold a list or a table (the reference app's Resource Manager, `w-[26rem]`).
        public static let popoverWidth: CGFloat = 400
    }

    /// The window's traffic-light row, for headers drawn under a transparent title bar.
    public enum Window {
        /// Height of the reference app's sidebar header row (`SESSION_HEADER_HEIGHT`, 36px).
        public static let headerHeight: CGFloat = 36
    }

    /// Drop shadows. the reference app keeps elevation subtle: menus and dialogs only.
    public struct Shadow: Sendable {
        let light: Double
        let dark: Double
        let radius: CGFloat
        let y: CGFloat

        /// Menus, tooltips and dialogs (the reference app `--core-v2-shadow-modal`: 0 8px 12px, 14%/50%).
        public static let modal = Shadow(light: 0.14, dark: 0.5, radius: 6, y: 8)
        /// Dragged rows (the reference app `--core-v2-shadow-drag`: 0 2px 8px, 12%/45%).
        public static let drag = Shadow(light: 0.12, dark: 0.45, radius: 4, y: 2)
        /// Content lifted over scrolled content (the reference app's floating composer: 0 4px 20px, 30%).
        public static let floating = Shadow(light: 0.12, dark: 0.3, radius: 10, y: 4)
    }
}

extension View {
    /// Applies a design-system shadow, stronger in dark mode as in the reference app.
    public func dsShadow(_ shadow: DS.Shadow) -> some View {
        modifier(DSShadowModifier(shadow: shadow))
    }
}

private struct DSShadowModifier: ViewModifier {
    let shadow: DS.Shadow

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // A CSS blur radius is twice SwiftUI's shadow radius.
        content.shadow(
            color: .black.opacity(colorScheme == .dark ? shadow.dark : shadow.light),
            radius: shadow.radius,
            y: shadow.y
        )
    }
}
