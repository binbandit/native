import SwiftUI

/// One choice in an `IconThemePicker`: an app icon look, as data, so options can come from the
/// app's own themes or from a plugin's icon set alike.
public struct IconThemeOption<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    /// The icon as the Dock shows it in each appearance; pass the same image twice when it has one.
    public let lightImage: Image
    public let darkImage: Image
    /// Who it comes from, when that isn't Native: a plugin's name ("Sunset Pack").
    public let badge: String?
    /// What it can't do here ("Mac only", "No Clear or Tinted"), or nil.
    public let note: String?

    public init(
        id: ID,
        title: String,
        lightImage: Image,
        darkImage: Image,
        badge: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.lightImage = lightImage
        self.darkImage = darkImage
        self.badge = badge
        self.note = note
    }

    func image(isDark: Bool) -> Image {
        isDark ? darkImage : lightImage
    }

    /// The badge and the note on one line, for the row's second line and VoiceOver's value.
    var detail: String? {
        let parts = [badge, note].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
