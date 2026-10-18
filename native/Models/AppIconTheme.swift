import AppAppearance
import Foundation

enum AppIconTheme: String, CaseIterable, Identifiable {
    case original, cobalt, fern, ember, prism, arcade, nightly

    var id: Self { self }
    var title: String { rawValue.capitalized }

    func imageName(isDark: Bool) -> String {
        "AppIcon-\(rawValue)-\(isDark ? "dark" : "light")"
    }

    /// The theme's compiled light and dark icons; the same in every channel.
    var images: AppIconImagePair {
        AppIconImagePair(light: .asset(imageName(isDark: false)), dark: .asset(imageName(isDark: true)))
    }
}
