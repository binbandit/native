import SwiftUI
import UIKit

/// System, light or dark, for the whole app.
enum CompanionAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app icon themes, matching the Mac's: each sets the accent too (`docs/decisions.md`,
/// "Accent follows the app icon theme"). Artwork comes from the icon owner as alternate icons
/// named `AppIcon-<Theme>`; until a theme's art ships, choosing it changes the accent and says so.
enum CompanionAppIcon: String, CaseIterable, Identifiable {
    case original, cobalt, fern, ember, prism, arcade

    static let key = "iconTheme"

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// Nil for the primary icon.
    var alternateIconName: String? {
        self == .original ? nil : "AppIcon-\(title)"
    }

    /// Switches the home-screen icon; returns why it couldn't, if it couldn't.
    @MainActor
    func apply() async -> String? {
        guard UIApplication.shared.supportsAlternateIcons else { return "This device can't change app icons." }
        guard UIApplication.shared.alternateIconName != alternateIconName else { return nil }
        do {
            try await UIApplication.shared.setAlternateIconName(alternateIconName)
            return nil
        } catch {
            return "The \(title) icon isn't in this build yet, so only the accent changed."
        }
    }
}
