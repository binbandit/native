import SwiftUI

/// A starting point as a ruled row: the verb in a fixed column, the object, a trailing detail and the
/// glyph for what a click does. The text sits on the composer's text inset and the hover wash spans
/// the column, like the hairlines between rows. The detail gives way first: when the object doesn't
/// fit beside it, it goes, rather than both being cut short. One button, so VoiceOver and touch get
/// one target with the verb and object as its label.
struct NewSessionLedgerRow: View {
    let point: NewSessionStartingPoint

    @State private var isHovered = false

    var body: some View {
        Button(action: point.perform) {
            ViewThatFits(in: .horizontal) {
                line(showsDetail: true)
                line(showsDetail: false)
            }
            .padding(.horizontal, DS.Composer.textInsets.leading)
            .frame(minHeight: max(NewSessionMetrics.ledgerRow, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background(isHovered ? Color.dsHover : .clear)
        .trackHover($isHovered)
        .accessibilityLabel("\(point.verb) \(point.object)")
        .accessibilityValue(point.detail ?? "")
        .accessibilityHint(point.hint)
        .help(point.hint)
    }

    private func line(showsDetail: Bool) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(point.verb)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .frame(width: NewSessionMetrics.verbColumn, alignment: .leading)
            Text(point.object)
                .font(.dsCallout)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.md)
            if showsDetail, let detail = point.detail {
                Text(detail)
                    .font(point.detailIsCode ? .dsMonoCaption : .dsBody)
                    .foregroundStyle(point.tone)
                    .lineLimit(1)
            }
            Image(systemName: point.glyph)
                .font(.dsBody)
                .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
                .frame(width: DS.Size.rowLeading)
                .accessibilityHidden(true)
        }
    }
}
