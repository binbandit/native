import SwiftUI

/// The row every usage notice uses: a glyph, the headline with its detail, and actions on the
/// right. It sits in the composer's stack as a section of its own, or on its own surface.
struct UsageBannerRow<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Size.navIcon, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: DS.Size.rowLeading)
            Text("\(Text(title).font(.dsBodyMedium).foregroundStyle(.dsTextPrimary))\(Text(detail.map { " · \($0)" } ?? "").font(.dsBody).foregroundStyle(.dsTextSecondary))")
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xs) {
                actions
            }
            .fixedSize()
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .frame(minHeight: DS.Size.controlMD + DS.Space.md)
        .accessibilityElement(children: .contain)
    }
}

/// How a usage notice is framed.
enum UsageBannerChrome {
    /// No frame of its own: a section in the composer's stack, which draws the rules around it.
    case section
    /// Its own outlined surface, matching the composer's, for placing above it.
    case card
}

extension View {
    @ViewBuilder
    func usageBannerChrome(_ chrome: UsageBannerChrome) -> some View {
        switch chrome {
        case .section:
            self
        case .card:
            let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            background(.dsSurface, in: shape)
                .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
                .dsShadow(.floating)
        }
    }
}
