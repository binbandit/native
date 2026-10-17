import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppIconPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                previewImage(for: preferences.theme)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("App icon")
                        .font(.title2.weight(.semibold))
                    Text("A little more you, in your Dock.")
                        .foregroundStyle(.secondary)
                    Text(preferences.theme.title)
                        .font(.callout.weight(.medium))
                }
            }

            Divider()

            HStack(spacing: 20) {
                Text("Icon appearance")
                Spacer(minLength: 0)
                if preferences.theme == .original {
                    Text("Follows macOS")
                        .font(.callout)
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
                preferences.theme == .original
                    ? "Default, Dark, Clear and Tinted appearances follow your Mac’s settings."
                    : "Choose Original to use your Mac’s Clear or Tinted icons."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(AppIconTheme.allCases) { theme in
                    themeButton(theme)
                }
            }
        }
        .padding(28)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: preferences.imageName)
    }

    private func themeButton(_ theme: AppIconTheme) -> some View {
        let selected = preferences.theme == theme

        return Button {
            preferences.theme = theme
        } label: {
            VStack(spacing: 4) {
                previewImage(for: theme)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                HStack(spacing: 5) {
                    Text(theme.title)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.callout)
                .frame(height: 18)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        } else {
            Image(theme.imageName(isDark: preferences.isDark))
        }
    }
}
