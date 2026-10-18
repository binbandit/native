import AppAppearance
import SwiftUI

/// The app icon rows of Settings ▸ Appearance: the base icon (a built-in theme or a plugin's icon set,
/// in the design system's picker) and its light or dark appearance. A celebration covers the base
/// while it lasts; Settings ▸ Celebrations is where it's chosen or put away.
struct AppearanceSettingsView: View {
    @Environment(AppIconPreferences.self) private var preferences

    var body: some View {
        SettingsRowGroup {
            SettingsRow("App icon", description: Text("A little more you, in your Dock."), detail: iconDetail) {
                IconThemePicker(
                    "App icon",
                    selection: Binding {
                        preferences.effectiveChoice
                    } set: {
                        preferences.select($0)
                    },
                    options: preferences.options.map { option in
                        IconThemeOption(
                            id: option.id, title: option.title,
                            lightImage: Self.image(option.preview, isDark: false),
                            darkImage: Self.image(option.preview, isDark: true),
                            badge: option.pluginName, note: option.limitation)
                    },
                    previewScheme: preferences.isDark ? .dark : .light
                )
                .accessibilityIdentifier("icon-theme-picker")
            }
            SettingsRow(
                "Icon appearance",
                description: Text("Light or dark, for icons other than Original."),
                detail: preferences.usesSystemIcon ? Text("Follows macOS") : nil
            ) {
                SettingsSelect(
                    label: "Icon appearance",
                    selection: Binding {
                        preferences.appearance
                    } set: {
                        preferences.appearance = $0
                    },
                    options: AppIconAppearance.allCases.map { .init(value: $0, title: $0.title) }
                )
                .disabled(preferences.usesSystemIcon)
            }
        }
    }

    private var iconDetail: Text? {
        if preferences.isCelebrating {
            return Text("\(preferences.displayName) is showing. Your choice returns when the celebration ends.")
        }
        return preferences.usesSystemIcon
            ? Text("Default, Dark, Clear and Tinted follow your Mac’s settings.") : nil
    }

    private static func image(_ preview: AppIconOption.Preview, isDark: Bool) -> Image {
        switch preview {
        case .bundle: PlatformAppIcon.bundledPreview
        case .image(let icons): PlatformAppIcon.preview(icons.image(isDark: isDark))
        }
    }
}
