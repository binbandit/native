import SwiftUI

/// The notification sound select: the reference app's outlined trigger over a native menu with the sounds
/// grouped as the reference app groups them (its own under a submenu, when the user has them), the user's
/// files, and ways to add or remove those.
struct SoundPicker: View {
    let sounds: NotificationSounds
    let onAddSound: () -> Void

    @State private var isHovered = false

    private var selection: Binding<SoundID> {
        Binding { sounds.preferences.selection } set: { sounds.select($0) }
    }

    private var title: String {
        guard sounds.preferences.selection != .none else { return "No Sound" }
        return sounds.selectedOption?.title ?? "Chime"
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
        .accessibilityLabel("Notification sound")
        .accessibilityValue(title)
    }

    @ViewBuilder
    private var options: some View {
        // One inline picker per group, all bound to the selection, so the menu checks the current
        // sound wherever it is.
        Picker("No Sound", selection: selection) {
            Text("No Sound").tag(SoundID.none)
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Section("Native") {
            picker("Native", sounds.catalog.native)
        }
        if !sounds.catalog.conductor.isEmpty {
            Menu("the reference app") {
                ForEach(sounds.catalog.conductor) { group in
                    Section(group.title) {
                        picker(group.title, group.options)
                    }
                }
            }
        }
        if !sounds.catalog.custom.isEmpty {
            Section("Your Sounds") {
                picker("Your Sounds", sounds.catalog.custom)
            }
        }
        Divider()
        Button("Add Sound…", action: onAddSound)
        if case .custom(let id) = sounds.preferences.selection, let option = sounds.selectedOption {
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
