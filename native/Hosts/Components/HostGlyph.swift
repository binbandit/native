import SwiftUI

/// A device's symbol in its color: the mark that stands for a host in rows, pickers and badges.
/// Graphite draws in secondary text, so an uncolored host stays quiet beside colored ones.
struct HostGlyph: View {
    let look: HostLook
    /// The symbol's point size.
    var size: CGFloat = DS.Size.navIcon
    var weight: Font.Weight = .regular
    /// Draws the symbol in tertiary text instead of its color, for a device that can't be used now.
    var isDimmed = false

    var body: some View {
        Image(systemName: look.symbol.systemImage)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .dsAccentPalette(look.tint.palette)
            .accessibilityHidden(true)
    }

    private var color: Color {
        if isDimmed { return .dsTextTertiary }
        return look.tint.palette.isMonochrome ? .dsTextSecondary : .dsAccentText
    }
}

#Preview("Host glyphs") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.lg) {
                ForEach(HostTint.allCases) { tint in
                    HostGlyph(look: HostLook(symbol: .mini, tint: tint), size: DS.Size.chromeGlyph)
                }
                HostGlyph(look: HostLook(symbol: .mini, tint: .cobalt), size: DS.Size.chromeGlyph, isDimmed: true)
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(HostSymbol.allCases) { symbol in
                    HostGlyph(look: HostLook(symbol: symbol, tint: .fern), size: DS.Size.statusGlyph)
                }
            }
        }
    }
}
