import SwiftUI

/// Settings ▸ Appearance ▸ Code font: the family, size and line height code is set in (code blocks,
/// diffs, tool output), and whether ligatures join. The code theme preview below shows it live.
struct CodeFontSettingsRow: View {
    static let rowID = SettingsRowID("appearance.code-font")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Code font", description: "The font, size and line height for code.",
            keywords: ["monospaced", "font", "size", "line height", "ligatures", "geist mono"])
    }

    @AppStorage(AppearancePreferences.codeFontFamilyKey) private var family = DSCodeFont.standard.family
    @AppStorage(AppearancePreferences.codeFontSizeKey) private var size = DSCodeFont.standard.size
    @AppStorage(AppearancePreferences.codeLineHeightKey) private var lineHeight = DSCodeFont.standard.lineHeight
    @AppStorage(AppearancePreferences.codeLigaturesKey) private var ligatures = DSCodeFont.standard.ligatures
    @AppStorage(AppearancePreferences.terminalUsesCodeFontKey) private var terminalUsesCodeFont = false

    var body: some View {
        SettingsRowGroup {
            SettingsRow(
                id: Self.rowID, "Code font",
                description: Text("For code blocks, diffs and tool output.")
            ) {
                HStack(spacing: DS.Space.md) {
                    SettingsSelect(
                        label: "Code font", selection: $family,
                        options: [.init(value: "", title: DSCodeFont.defaultFamilyName)]
                            + DSCodeFont.installedFamilies.map { .init(value: $0, title: $0) }
                            + (family.isEmpty || DSCodeFont.installedFamilies.contains(family)
                                ? [] : [.init(value: family, title: "\(family) (not installed)")]),
                        width: SettingsMetrics.selectWidth * 1.4)
                    SettingsSelect(
                        label: "Code size", selection: $size,
                        options: DSCodeFont.sizes.map { .init(value: $0, title: "\(Int($0)) pt") },
                        width: SettingsMetrics.selectWidth * 0.6)
                }
            }
            SettingsRow("Line height") {
                SettingsSelect(
                    label: "Line height", selection: $lineHeight,
                    options: DSCodeFont.lineHeights.map {
                        .init(value: $0, title: $0.formatted(.number.precision(.fractionLength(0...2))))
                    })
            }
            SettingsRow(
                "Ligatures",
                description: Text("Join character pairs such as -> and != in fonts that have programming ligatures.")
            ) {
                SettingsSwitch("Ligatures", isOn: $ligatures)
            }
            SettingsRow(
                "Use the same font in the terminal",
                description: Text("Set the terminal in this font and size too, instead of its own font settings.")
            ) {
                SettingsSwitch("Use the same font in the terminal", isOn: $terminalUsesCodeFont)
            }
        }
    }
}
