import AppKit
import SwiftUI
import Terminal

/// Settings › Terminal: where the terminal's settings come from (Native's or the user's Ghostty
/// config), then Native's own font, cursor, scrollback and colors, with a preview in the
/// terminal's colors. Changes apply to open terminals right away.
struct TerminalSettingsPage: View {
    static let ghosttyRow = SettingsRowID("terminal.ghostty")
    static let importRow = SettingsRowID("terminal.import")
    static let fontRow = SettingsRowID("terminal.font")
    static let sizeRow = SettingsRowID("terminal.size")
    static let cursorRow = SettingsRowID("terminal.cursor")
    static let scrollbackRow = SettingsRowID("terminal.scrollback")
    static let colorsRow = SettingsRowID("terminal.colors")
    static let shellRow = SettingsRowID("terminal.shell")

    /// Wide enough for most font family names.
    static let fontSelectWidth: CGFloat = 220

    let store: TerminalStore

    @State private var families: [String] = []
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsAccentPalette) private var palette
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.dsTransparency) private var transparency
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var preferences = store.preferences
        let usesGhostty = preferences.settings.usesGhosttyConfig
        SettingsPage {
            SettingsHeader("Terminal", description: Text("Each task's terminal, opened with ⌃` in its folder."))
            TerminalGhosttySection(store: store)
            SettingsRowGroup {
                TerminalShellRow(store: store)
            }
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SettingsSubheading(
                    "Native's terminal settings",
                    note: usesGhostty ? "Not in use while your Ghostty settings are on." : nil)
                TerminalSettingsPreview(settings: preferences.settings, colors: colors)
                SettingsRowGroup {
                    SettingsRow(id: Self.fontRow, "Font", description: Text("Any monospaced font on this Mac.")) {
                        SettingsSelect(
                            label: "Font",
                            selection: $preferences.settings.fontFamily,
                            options: fontOptions(current: preferences.settings.fontFamily),
                            width: Self.fontSelectWidth
                        )
                    }
                    SettingsRow(id: Self.sizeRow, "Font size") {
                        SettingsSelect(
                            label: "Font size",
                            selection: $preferences.settings.fontSize,
                            options: stride(
                                from: TerminalSettings.fontSizes.lowerBound,
                                through: TerminalSettings.fontSizes.upperBound, by: 1
                            ).map { .init(value: $0, title: "\(Int($0)) pt") }
                        )
                    }
                    SettingsRow(id: Self.cursorRow, "Cursor") {
                        SettingsSelect(
                            label: "Cursor",
                            selection: $preferences.settings.cursor.style,
                            options: TerminalCursorStyle.allCases.map { .init(value: $0, title: $0.title) }
                        )
                    }
                    SettingsRow("Blink the cursor") {
                        SettingsSwitch("Blink the cursor", isOn: $preferences.settings.cursor.blinks)
                    }
                    SettingsRow(
                        id: Self.scrollbackRow,
                        "Scrollback",
                        description: Text("Lines each terminal keeps above the screen. Applies to new terminals.")
                    ) {
                        SettingsSelect(
                            label: "Scrollback",
                            selection: $preferences.settings.scrollback,
                            options: scrollbackOptions(current: preferences.settings.scrollback)
                        )
                    }
                    colorsRow
                }
            }
            .disabled(usesGhostty)
            .opacity(usesGhostty ? 0.5 : 1)
        }
        .task { families = Self.monospacedFamilies() }
        .onChange(of: appearanceKey, initial: true) { _, key in
            let appearance = TerminalAppearance(key.colorScheme)
            store.setAppearance(
                appearance,
                chrome: .designSystem(
                    appearance: appearance, palette: key.palette, lightTone: key.lightTone, darkTone: key.darkTone),
                transparency: key.transparency)
        }
    }

    @ViewBuilder private var colorsRow: some View {
        switch store.preferences.settings.colors {
        case .app:
            SettingsRow(
                id: Self.colorsRow, "Colors",
                description: Text("Native's colors, in light and dark. Import from Ghostty to use your theme instead.")
            ) {
                SettingsValue("Native")
            }
        case .imported(let imported):
            SettingsRow(
                id: Self.colorsRow, "Colors",
                description: Text("Imported from Ghostty\(imported.themeTitle.map { ": \($0)" } ?? "").")
            ) {
                Button("Use Native's Colors") { store.preferences.settings.colors = .app }
            }
        }
    }

    private var colors: TerminalColors {
        let appearance = TerminalAppearance(colorScheme)
        return TerminalStyle(
            settings: store.preferences.settings, appearance: appearance, appTheme: store.appTheme,
            appChrome: .designSystem(
                appearance: appearance, palette: palette, lightTone: lightTone, darkTone: darkTone)
        ).colors
    }

    private func fontOptions(current: String?) -> [SettingsSelect<String?>.Option] {
        // An imported family that isn't installed still shows, so the select never goes blank.
        let names = families + (current.map { families.contains($0) ? [] : [$0] } ?? [])
        return [.init(value: nil, title: "Geist Mono (Default)")] + names.map { .init(value: $0, title: $0) }
    }

    private func scrollbackOptions(current: TerminalScrollback) -> [SettingsSelect<TerminalScrollback>.Option] {
        let choices =
            TerminalScrollback.choices.contains(current)
            ? TerminalScrollback.choices : TerminalScrollback.choices + [current]
        return choices.map { .init(value: $0, title: $0.title) }
    }

    /// Installed monospaced families other than the default, by name.
    static func monospacedFamilies() -> [String] {
        let manager = NSFontManager.shared
        let fixedPitch = NSFontTraitMask.fixedPitchFontMask.rawValue
        return manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."), family != "Geist Mono",
                let traits = manager.availableMembers(ofFontFamily: family)?.first?[3] as? NSNumber
            else { return false }
            return traits.uintValue & fixedPitch != 0
        }
    }

    private var appearanceKey: TerminalAppearanceKey {
        TerminalAppearanceKey(
            colorScheme: colorScheme, palette: palette, lightTone: lightTone, darkTone: darkTone,
            transparency: TerminalTransparency(
                transparency, reduceTransparency: reduceTransparency,
                isTrueBlack: colorScheme == .dark && darkTone == .trueBlack))
    }
}

extension TerminalScrollback {
    var title: String {
        switch self {
        case .lines(let count): "\(count.formatted()) lines"
        case .unlimited: "Unlimited"
        }
    }
}

extension TerminalCursorStyle {
    var title: String {
        switch self {
        case .block: "Block"
        case .bar: "Bar"
        case .underline: "Underline"
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Terminal settings") {
    DSPreviewPair {
        TerminalSettingsPage(store: TerminalPreviewFixtures.store())
            .settingsPreviewPage()
    }
    .environment(SettingsPresentation())
}
#endif
