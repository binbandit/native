import SwiftUI

/// The few sizes the hosts UI needs beyond the design system's, in one place so its views carry no
/// literals.
enum HostsMetrics {
    /// The waiting loader beside a device: a status glyph's square.
    static let loader = DS.Size.statusGlyph
    /// A device's glyph in a list row: the sidebar's leading-slot glyph size.
    static let rowGlyph = DS.Size.navIcon
    /// A device's glyph on its Settings tile. Device symbols are wide and short, so they take a
    /// size above the tile's usual glyph (and a regular weight) to fill it as much as an icon does.
    static let tileGlyph: CGFloat = 20
    /// A device's glyph beside callout text, in the picker and a session's header.
    static let calloutGlyph = DS.Size.statusGlyph
    /// The device picker: wide enough for a host's name, its state and a checkout path.
    static let pickerWidth = DS.Size.hoverCardWidth
    /// The sign-in sheet: a readable measure for its steps, with room for a command beside its copy
    /// button.
    static let signInSheetWidth: CGFloat = 560
    /// Past this the sign-in sheet's steps scroll, so the sheet fits a small window.
    static let signInSheetMaxHeight: CGFloat = 600
    /// A device code, in mono at the second title's size, to read off the screen while typing it.
    static let deviceCodeSize: CGFloat = 20
}
