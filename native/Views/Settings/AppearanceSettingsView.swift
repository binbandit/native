import AppAppearance
import SwiftUI

/// The app icon: what the Dock shows now, the base icon (a built-in theme or a plugin's icon set, in
/// the design system's picker), and its light or dark appearance. A celebration covers the base while
/// it lasts; Settings ▸ Celebrations is where it's chosen or put away.
struct AppearanceSettingsView: View {
    @Environment(AppIconPreferences.self) private var preferences
    @Environment(SettingsPresentation.self) private var settings: SettingsPresentation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            HStack(spacing: DS.Space.xl) {
                currentPreview
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: DS.AppIcon.hero, height: DS.AppIcon.hero)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("App icon")
                        .font(.dsTitle2)
                    Text("A little more you, in your Dock.")
                        .foregroundStyle(.secondary)
                    Text(preferences.displayName)
                        .font(.dsCalloutMedium)
                }
            }

            Divider()

            HStack(spacing: DS.Space.xl) {
                Text("Icon")
                Spacer(minLength: 0)
                IconThemePicker(
                    "App icon",
                    selection: Binding(get: { preferences.effectiveChoice }, set: { preferences.select($0) }),
                    options: preferences.options.map(Self.pickerOption),
                    previewScheme: preferences.isDark ? .dark : .light
                )
                .accessibilityIdentifier("icon-theme-picker")
            }

            HStack(spacing: DS.Space.xl) {
                Text("Icon appearance")
                Spacer(minLength: 0)
                if preferences.usesSystemIcon {
                    Text("Follows macOS")
                        .font(.dsCallout)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Icon appearance", selection: $preferences.appearance) {
                        ForEach(AppIconAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            HStack(spacing: DS.Space.md) {
                Text(note)
                    .font(.dsCallout)
                    .foregroundStyle(.secondary)
                if preferences.isCelebrating, let settings {
                    Button("Celebrations…") { settings.open(.celebrations) }
                        .buttonStyle(.ds(.ghost, size: .medium))
                }
            }
        }
        .padding(DS.Space.xxl)
        .animation(reduceMotion ? nil : .dsQuick, value: preferences.currentImage)
    }

    private var note: String {
        if preferences.isCelebrating {
            return "A celebration is on your icon. Your chosen icon returns when it ends."
        }
        return preferences.usesSystemIcon
            ? "Default, Dark, Clear and Tinted appearances follow your Mac’s settings."
            : "Choose Original to use your Mac’s Clear or Tinted icons."
    }

    private var currentPreview: Image {
        preferences.currentImage.map(PlatformAppIcon.preview) ?? PlatformAppIcon.bundledPreview
    }

    private static func pickerOption(_ option: AppIconOption) -> IconThemeOption<AppIconOption.ID> {
        let (light, dark) =
            switch option.preview {
            case .bundle: (PlatformAppIcon.bundledPreview, PlatformAppIcon.bundledPreview)
            case .image(let icons): (PlatformAppIcon.preview(icons.light), PlatformAppIcon.preview(icons.dark))
            }
        return IconThemeOption(
            id: option.id, title: option.title, lightImage: light, darkImage: dark, badge: option.pluginName,
            note: option.limitation)
    }
}
