enum AppIconTheme: String, CaseIterable, Identifiable {
    case original, cobalt, fern, ember, prism, arcade, nightly

    var id: Self { self }
    var title: String { rawValue.capitalized }

    func imageName(isDark: Bool) -> String {
        "AppIcon-\(rawValue)-\(isDark ? "dark" : "light")"
    }
}
