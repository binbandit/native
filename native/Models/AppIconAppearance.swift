/// A themed icon's light or dark artwork. `system` (stored under that name for good) matches Native's
/// own appearance, so the icon goes dark with the app, whether the app follows the Mac or is set to
/// light or dark in Settings ▸ Appearance.
enum AppIconAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
