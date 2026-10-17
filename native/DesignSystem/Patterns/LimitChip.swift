import SwiftUI

/// The compact form of a usage limit, for the sidebar footer and the status bar: a tinted glyph and
/// "5-hour limit · 42 min" or "weekly 90%". The full sentence is its tooltip and accessibility label.
public struct LimitChip: View {
    let status: LimitStatus
    let action: (() -> Void)?

    /// - Parameter action: Opens the details, e.g. the banner's pane.
    public init(status: LimitStatus, action: (() -> Void)? = nil) {
        self.status = status
        self.action = action
    }

    private var tone: Color {
        status.level == .reached ? .dsDanger : .dsWarning
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            let label = HStack(spacing: DS.Space.xs) {
                Image(systemName: status.level == .reached ? "exclamationmark.octagon.fill" : "gauge.with.dots.needle.67percent")
                    .font(.system(size: 10))
                    .foregroundStyle(tone)
                Text(status.compactText(now: context.date))
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(height: 20)
            .background(tone.opacity(0.1), in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .help(status.line(now: context.date))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.line(now: context.date))

            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
        .fixedSize()
    }
}

#Preview("Limit chips") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            ForEach(GalleryFixtures.limits) { status in
                LimitChip(status: status)
            }
        }
    }
}
