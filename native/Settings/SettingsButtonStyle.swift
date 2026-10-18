import SwiftUI

/// An action in Settings: an outlined button, 32pt like every other control so rows line up, with
/// 14pt text and a 6pt radius. Its label is a verb ("Reset ID", "Show Log"), which with the missing
/// chevron tells it apart from a `SettingsSelect`. A destructive role draws the label in red.
///
///     Button("Clear Index") { … }.buttonStyle(.settings)
struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsButtonBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
}

private struct SettingsButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        configuration.label
            .labelStyle(SettingsButtonLabelStyle())
            .font(SettingsTextStyle.body.font)
            .lineLimit(1)
            .foregroundStyle(configuration.role == .destructive ? Color.dsDanger : .dsTextPrimary)
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: SettingsMetrics.controlHeight)
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(shape)
            // Half strength while disabled, so an action that can't run now looks it.
            .opacity(isEnabled ? 1 : 0.5)
            .dsHitTarget(SettingsMetrics.controlHeight)
            .dsFocusShape(shape)
            .trackHover($isHovered)
    }

    private var fill: Color {
        guard isEnabled else { return .dsBackground }
        return configuration.isPressed ? .dsPressed : isHovered ? .dsHover : .dsBackground
    }
}

/// A glyph a size below the text, 6pt before the title.
private struct SettingsButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Space.sm) {
            configuration.icon
                .font(.system(size: SettingsMetrics.buttonGlyph))
            configuration.title
        }
    }
}

#Preview("Settings button") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Button("Reset ID") {}
            Button("Show Log", systemImage: "doc.text.magnifyingglass") {}
            Button("Remove", role: .destructive) {}
            Button("Clear Index") {}.disabled(true)
        }
        .buttonStyle(.settings)
        .padding(DS.Space.xl)
    }
}
