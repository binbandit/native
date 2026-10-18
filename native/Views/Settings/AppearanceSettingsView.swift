import AppAppearance
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
                    : preferences.isCelebrating
                        ? "Your chosen icon returns when the celebration ends. Restore it now in Celebrations."
                        : "Choose Original to use your Mac’s Clear or Tinted icons."
            )
            .font(.dsCallout)
            .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.lg), count: DS.AppIcon.columns),
                spacing: DS.Space.lg
            ) {
                ForEach(preferences.options) { option in
                    optionButton(option)
                }
            }

        }
        .padding(DS.Space.xxl)
        .animation(reduceMotion ? nil : .dsQuick, value: preferences.currentImage)
    }

    private func optionButton(_ option: AppIconOption) -> some View {
        let selected = preferences.effectiveChoice == option.id

        return Button {
            preferences.select(option.id)
        } label: {
            VStack(spacing: DS.Space.xs) {
                previewImage(option.preview)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: DS.AppIcon.tile, height: DS.AppIcon.tile)
                HStack(spacing: DS.Space.xs) {
                    Text(option.title)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.dsAccent)
                    }
                }
                .font(.dsCallout)
                .frame(height: DS.AppIcon.labelHeight)
                if let note = option.limitation ?? option.pluginName {
                    Text(note)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .accessibilityLabel(option.title)
        .accessibilityValue(selected ? "Selected" : option.limitation ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("icon-theme-\(option.id.rawValue)")
        .help("Use the \(option.title) icon")
    }

    private func previewImage(_ preview: AppIconOption.Preview) -> Image {
        switch preview {
        case .bundle: PlatformAppIcon.bundledPreview
        case .image(let icons): PlatformAppIcon.preview(icons.image(isDark: preferences.isDark))
        }
    }

    private var currentPreview: Image {
        preferences.currentImage.map(PlatformAppIcon.preview) ?? PlatformAppIcon.bundledPreview
    }
}
