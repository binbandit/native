import SwiftUI

/// A usage notice that isn't a provider limit (a nearly full context window), drawn like the
/// design system's `LimitBanner` so warnings above the composer look and read alike: a tinted
/// glyph, a headline with its detail under it, and actions on the right.
struct UsageBannerRow<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String?
    var chrome: UsageBannerChrome = .card
    @ViewBuilder var actions: Actions

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: systemImage)
                .font(.dsCallout)
                .foregroundStyle(tint)
                .frame(width: DS.Size.rowLeading, height: DS.Size.statusGlyph + DS.Space.xs)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let detail {
                    Text(detail)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            .tracking(DS.Tracking.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xs) {
                actions
            }
            .fixedSize()
        }
        .padding(.vertical, DS.Space.md)
        .padding(.horizontal, DS.Space.lg)
        .background(chrome == .card ? Color.dsSurfaceRaised : .clear, in: shape)
        .overlay {
            if chrome == .card {
                shape.strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// How a usage notice is framed.
enum UsageBannerChrome {
    /// Its own surface with a tinted edge, like `LimitBanner`, for placing above the composer.
    case card
    /// No frame: a section inside the composer's stack, which draws the rules around it.
    case section
}
