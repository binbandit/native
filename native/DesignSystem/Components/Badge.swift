import SwiftUI

/// A small label: Factory's outlined nav badge ("Beta"), a soft tinted tag, or Conductor's
/// uppercase mono badge ("NEW", "PRO").
public struct Badge: View {
    public enum Tone: Sendable {
        case neutral, accent, success, warning, danger, info

        var color: Color {
            switch self {
            case .neutral: .dsTextSecondary
            case .accent: .dsAccentText
            case .success: .dsSuccess
            case .warning: .dsWarning
            case .danger: .dsDanger
            case .info: .dsInfo
            }
        }
    }

    public enum Style: Sendable {
        /// 1pt border, 2pt radius, 10pt medium (Factory `NavigationBadge`).
        case outline
        /// A 12% wash of the tone, no border.
        case soft
        /// Uppercase Geist Mono with wide tracking (Conductor `Badge`).
        case mono
    }

    let text: String
    let tone: Tone
    let style: Style

    public init(_ text: String, tone: Tone = .neutral, style: Style = .outline) {
        self.text = text
        self.tone = tone
        self.style = style
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        Group {
            switch style {
            case .outline, .soft:
                Text(text)
                    .font(.ds(10, weight: .medium))
                    .tracking(DS.Tracking.tight)
            case .mono:
                Text(text.uppercased())
                    .font(.ds(10, weight: .medium, design: .mono))
                    .tracking(DS.Tracking.wide)
            }
        }
        .lineLimit(1)
        .foregroundStyle(tone.color)
        .padding(.horizontal, DS.Space.sm)
        .frame(minHeight: 16)
        .background {
            switch style {
            case .outline: shape.fill(.dsSurface)
            case .soft: shape.fill(tone.color.opacity(0.12))
            case .mono: shape.fill(.clear)
            }
        }
        .overlay {
            if style != .soft {
                shape.strokeBorder(tone == .neutral ? Color.dsBorderInner : tone.color.opacity(0.4), lineWidth: 1)
            }
        }
        .fixedSize()
    }
}

#Preview("Badges") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Badge("Beta")
            Badge("Running", tone: .accent, style: .soft)
            Badge("Merged", tone: .success, style: .soft)
            Badge("Failed", tone: .danger, style: .soft)
            Badge("New", tone: .accent, style: .mono)
            Badge("Pro", style: .mono)
        }
    }
}
