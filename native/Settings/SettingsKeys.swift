import SwiftUI

/// A key or chord drawn as the reference app draws them: glyphs side by side, with Return as a
/// corner-down-left arrow because the ↵ character renders inconsistently across fonts.
struct KeyGlyphs: View {
    /// Glyphs such as "⌘⇧M" or "⌃Tab"; each "↵" is Return.
    let keys: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(keys.split(separator: "↵", omittingEmptySubsequences: false).enumerated()), id: \.offset) {
                index, text in
                if index > 0 {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: SettingsMetrics.returnGlyph, weight: .medium))
                        .padding(.horizontal, 1)
                        .accessibilityLabel("Return")
                }
                if !text.isEmpty {
                    Text(text)
                }
            }
        }
    }
}

/// the reference app's shortcut pill: 32pt tall, fully rounded, a muted fill and medium glyphs.
struct SettingsKeycap: View {
    let keys: String

    var body: some View {
        KeyGlyphs(keys: keys)
            .settingsText(.bodyMedium)
            .foregroundStyle(.dsTextSecondary)
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: SettingsMetrics.controlHeight)
            .background(.dsSurfaceSunken, in: .capsule)
            .fixedSize()
    }
}

/// The shortcut hint inside the search field (the reference app's `⌘F` cap: 16pt tall, 4pt radius,
/// outlined, glyphs 4pt apart).
struct SearchShortcutHint: View {
    let parts: [String]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: DS.Space.xs) {
            ForEach(parts, id: \.self) { Text($0) }
        }
        .font(.ds(SettingsMetrics.hintFontSize, weight: .medium))
        .foregroundStyle(.dsTextSecondary)
        .padding(.horizontal, DS.Space.xs)
        .frame(
            minWidth: SettingsMetrics.hintHeight + DS.Space.xs, minHeight: SettingsMetrics.hintHeight,
            maxHeight: SettingsMetrics.hintHeight
        )
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .fixedSize()
        .accessibilityHidden(true)
    }
}
