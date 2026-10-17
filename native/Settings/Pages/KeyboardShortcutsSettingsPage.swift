import SwiftUI

extension SettingsPane.ID {
    static let keyboardShortcuts = Self("keyboard-shortcuts")
}

extension SettingsPane {
    static let keyboardShortcuts = SettingsPane(
        id: .keyboardShortcuts,
        title: "Keyboard shortcuts",
        systemImage: "keyboard",
        group: .personal,
        order: 20,
        keywords: ["keys", "hotkeys"],
        searchEntries: {
            ShortcutReference.groups(followUp: .defaultValue).flatMap(\.shortcuts).map { shortcut in
                SettingsSearchEntry(
                    id: ShortcutReference.rowID(shortcut), title: shortcut.title, description: shortcut.note ?? "",
                    keywords: shortcut.keywords)
            }
        },
        content: { KeyboardShortcutsSettingsPage() }
    )
}

/// A read-only reference in the layout of the reference app's Keyboard shortcuts page: groups 32pt apart,
/// each a muted heading over an outlined list of rows with pill keycaps.
struct KeyboardShortcutsSettingsPage: View {
    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Keyboard shortcuts",
                description: Text("Tab, the arrow keys, Space and Escape work as they do everywhere on macOS.")
            )
            VStack(alignment: .leading, spacing: DS.Space.xxxl) {
                ForEach(ShortcutReference.groups(followUp: followUp)) { group in
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SettingsSubheading(group.title, note: group.note)
                        ShortcutList(shortcuts: group.shortcuts)
                    }
                }
            }
        }
    }
}

/// the reference app `divide-y rounded-lg border`.
private struct ShortcutList: View {
    let shortcuts: [ShortcutReference.Shortcut]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                if index > 0 {
                    SeparatorLine()
                }
                ShortcutRow(shortcut: shortcut)
            }
        }
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}

private struct ShortcutRow: View {
    let shortcut: ShortcutReference.Shortcut

    var body: some View {
        HStack(spacing: DS.Space.xxl) {
            VStack(alignment: .leading, spacing: 0) {
                Text(shortcut.title)
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let note = shortcut.note {
                    Text(note)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xs) {
                ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { index, keys in
                    if index > 0, let joiner = shortcut.joiner {
                        Text(joiner)
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                    }
                    SettingsKeycap(keys: keys)
                }
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .accessibilityElement(children: .combine)
        .settingsRevealTarget(ShortcutReference.rowID(shortcut))
    }
}
