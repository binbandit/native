import SwiftUI

/// One trigger's sound select: the settings select's outlined trigger over a native menu with
/// Native's sounds, the sounds folder's files in a submenu named after it, the files the user added,
/// and ways to add or remove those.
struct SoundPicker: View {
    let sounds: NotificationSounds
    let trigger: SoundTrigger
    let onAddSound: () -> Void

    @State private var isHovered = false

    private var selection: Binding<SoundID> {
        Binding { sounds.preferences.sound(for: trigger) } set: { sounds.select($0, for: trigger) }
    }

    private var title: String {
        sounds.option(for: trigger)?.title ?? ""
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Menu {
            options
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(title)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: SettingsMetrics.chevronGlyph, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
            }
            .padding(.leading, DS.Space.lg)
            .padding(.trailing, DS.Space.md)
            .frame(width: SoundsSettingsPage.selectWidth, height: SettingsMetrics.controlHeight)
            .background(isHovered ? Color.dsHover : Color.dsBackground, in: shape)
            .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .contentShape(.focusEffect, shape)
        .trackHover($isHovered)
        .accessibilityLabel("Sound for \(trigger.title.lowercased())")
        .accessibilityValue(title)
    }

    @ViewBuilder
    private var options: some View {
        // One inline picker per group, all bound to the selection, so the menu checks the current
        // sound wherever it is.
        Section("Native") {
            picker("Native", sounds.catalog.native)
        }
        // A submenu, so a folder of many files doesn't push the rest of the menu off screen.
        if let folder = sounds.catalog.folder, !folder.sounds.isEmpty {
            Menu(folder.name) {
                picker(folder.name, folder.sounds)
            }
        }
        if !sounds.catalog.custom.isEmpty {
            Section("Your Sounds") {
                picker("Your Sounds", sounds.catalog.custom)
            }
        }
        Divider()
        Button("Add Sound…", action: onAddSound)
        if case .custom(let id) = sounds.preferences.sound(for: trigger), let option = sounds.option(for: trigger) {
            Button("Remove “\(option.title)”") {
                sounds.removeSound(id)
            }
        }
    }

    private func picker(_ label: String, _ options: [SoundOption]) -> some View {
        Picker(label, selection: selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
