import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppIconPreferences.self) private var preferences
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

            Text(
                preferences.usesSystemIcon
                    ? "Default, Dark, Clear and Tinted appearances follow your Mac’s settings."
                    : preferences.isHalloweenActive
                        ? "Your chosen icon returns after November 7. Turn Halloween off to switch back now."
                        : "Choose Original to use your Mac’s Clear or Tinted icons."
            )
            .font(.dsCallout)
            .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.lg), count: DS.AppIcon.columns),
                spacing: DS.Space.lg
            ) {
                ForEach(AppIconTheme.allCases) { theme in
                    themeButton(theme)
                }
            }

            if preferences.isHalloweenAvailable {
                Divider()
                HStack(spacing: DS.Space.lg) {
                    Image(preferences.halloweenImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: DS.AppIcon.seasonalPreview, height: DS.AppIcon.seasonalPreview)
                        .accessibilityHidden(true)
                    Toggle(isOn: $preferences.halloweenEnabled) {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text("Halloween edition").font(.dsHeadline)
                            Text("October 1 – November 7 · Returns to your chosen icon afterwards.")
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel("Halloween edition")
                    .accessibilityHint("Available October 1 through November 7. Restores your chosen icon afterwards.")
                    .accessibilityIdentifier("icon-halloween-enabled")
                }
            }
        }
        .padding(DS.Space.xxl)
        .animation(reduceMotion ? nil : .dsQuick, value: preferences.imageName)
    }

    private func themeButton(_ theme: AppIconTheme) -> some View {
        let selected = preferences.theme == theme

        return Button {
            preferences.selectTheme(theme)
        } label: {
            VStack(spacing: DS.Space.xs) {
                previewImage(for: theme)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: DS.AppIcon.tile, height: DS.AppIcon.tile)
                HStack(spacing: DS.Space.xs) {
                    Text(theme.title)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.dsAccent)
                    }
                }
                .font(.dsCallout)
                .frame(height: DS.AppIcon.labelHeight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.AppIcon.tilePadding)
            .background(
                selected ? Color.dsAccent.opacity(DS.AppIcon.selectedOpacity) : .clear,
                in: .rect(cornerRadius: DS.Radius.panel)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.panel)
                    .strokeBorder(selected ? Color.dsAccent : .clear, lineWidth: DS.AppIcon.selectedBorder)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("icon-theme-\(theme.rawValue)")
        .help("Use the \(theme.title) icon")
    }

    private func previewImage(for theme: AppIconTheme) -> Image {
        if theme == .original {
            PlatformAppIcon.bundledPreview
        } else {
            Image(theme.imageName(isDark: preferences.isDark))
        }
    }

    private var currentPreview: Image {
        preferences.isHalloweenActive ? Image(preferences.imageName) : previewImage(for: preferences.theme)
    }
}
