import AppKit
import SwiftUI
import Terminal

/// Settings › Terminal: the font, its size and how much scrollback each terminal keeps, with a
/// preview in the terminal's own colors. Changes apply to open terminals right away.
struct TerminalSettingsPage: View {
    static let fontRow = SettingsRowID("terminal.font")
    static let sizeRow = SettingsRowID("terminal.size")
    static let scrollbackRow = SettingsRowID("terminal.scrollback")

    /// Wide enough for most font family names.
    static let fontSelectWidth: CGFloat = 220

    let preferences: TerminalPreferences

    @State private var families: [String] = []
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsAccentPalette) private var palette

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsHeader("Terminal", description: Text("Each task's terminal, opened with ⌃` in its folder."))
            TerminalSettingsPreview(settings: preferences.settings, colors: colors)
            SettingsRowGroup {
                SettingsRow(id: Self.fontRow, "Font", description: Text("Any monospaced font on this Mac.")) {
                    SettingsSelect(
                        label: "Font",
                        selection: $preferences.settings.fontFamily,
                        options: [.init(value: nil, title: "Geist Mono (Default)")]
                            + families.map { .init(value: $0, title: $0) },
                        width: Self.fontSelectWidth
                    )
                }
                SettingsRow(id: Self.sizeRow, "Font size") {
                    SettingsSelect(
                        label: "Font size",
                        selection: $preferences.settings.fontSize,
                        options: stride(
                            from: TerminalSettings.fontSizes.lowerBound, through: TerminalSettings.fontSizes.upperBound,
                            by: 1
                        ).map { .init(value: $0, title: "\(Int($0)) pt") }
                    )
                }
                SettingsRow(
                    id: Self.scrollbackRow,
                    "Scrollback",
                    description: Text("Lines each terminal keeps above the screen. Applies to new terminals.")
                ) {
                    SettingsSelect(
                        label: "Scrollback",
                        selection: $preferences.settings.scrollback,
                        options: TerminalScrollback.allCases.map { .init(value: $0, title: $0.title) }
                    )
                }
            }
        }
        .task { families = Self.monospacedFamilies() }
    }

    private var colors: TerminalColors {
        let appearance = TerminalAppearance(colorScheme)
        return TerminalTheme.named(preferences.settings.themeID).colors(
            for: appearance, appChrome: .designSystem(appearance: appearance, palette: palette))
    }

    /// Installed monospaced families other than the default, by name.
    private static func monospacedFamilies() -> [String] {
        let manager = NSFontManager.shared
        let fixedPitch = NSFontTraitMask.fixedPitchFontMask.rawValue
        return manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."), family != "Geist Mono",
                let traits = manager.availableMembers(ofFontFamily: family)?.first?[3] as? NSNumber
            else { return false }
            return traits.uintValue & fixedPitch != 0
        }
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

/// A few lines of a shell session in the chosen font and the terminal's colors.
private struct TerminalSettingsPreview: View {
    let settings: TerminalSettings
    let colors: TerminalColors

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            (color(2, "native") + color(nil, " % git status"))
            color(nil, "On branch main")
            (color(nil, "  modified:   ") + color(1, "docs/terminal.md"))
            (color(nil, "  new file:   ") + color(2, "native/Terminal/"))
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.lg)
        .background(Color(colors.chrome.background), in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.dsSeparator)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the terminal font")
    }

    private var font: Font {
        let size = settings.fontSize
        guard let family = settings.fontFamily else {
            return Font(DSTypography.nsFont(size: size, design: .mono))
        }
        return .custom(family, fixedSize: size)
    }

    /// `text` in palette color `index`, or the default text color.
    private func color(_ index: Int?, _ text: String) -> Text {
        let rgb = index.map { colors.palette[$0] } ?? colors.chrome.foreground
        return Text(text).foregroundStyle(Color(rgb))
    }
}

extension Color {
    init(_ rgb: TerminalRGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}
