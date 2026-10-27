import SwiftUI

/// The one inline notice: a tinted glyph, a title, up to two supporting lines and trailing
/// actions that move below the message at narrow widths, on a raised surface outlined in the tone.
/// `ErrorState` and `LimitBanner` are built on it; use it directly for other notices (offline,
/// sign-in expired) rather than inventing one.
public struct NoticeBanner<Actions: View>: View {
    public enum Tone: Sendable {
        case info, success, warning, danger

        var color: Color {
            switch self {
            case .info: .dsInfo
            case .success: .dsSuccess
            case .warning: .dsWarning
            case .danger: .dsDanger
            }
        }

        var defaultSymbol: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .danger: "exclamationmark.octagon"
            }
        }
    }

    let tone: Tone
    let systemImage: String?
    let title: String
    let detail: String?
    let footnote: String?
    let actions: Actions

    /// - Parameters:
    ///   - detail: The main supporting line, in secondary text.
    ///   - footnote: A quieter line, e.g. the provider's own message.
    ///   - actions: At most one primary button, plus a dismiss if the notice can go away.
    public init(
        tone: Tone,
        systemImage: String? = nil,
        title: String,
        detail: String? = nil,
        footnote: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.tone = tone
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.footnote = footnote
        self.actions = actions()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                message
                actionRow.fixedSize()
            }
            VStack(alignment: .leading, spacing: Actions.self == EmptyView.self ? 0 : DS.Space.md) {
                message
                ViewThatFits(in: .horizontal) {
                    actionRow.fixedSize()
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        actions
                    }
                    .fixedSize()
                }
                .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            }
        }
        .padding(.vertical, DS.Space.md)
        .padding(.horizontal, DS.Space.lg)
        .background(.dsSurfaceRaised, in: shape)
        .overlay { shape.strokeBorder(tone.color.opacity(0.35), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        // The glyph and the actions' labels sit on the title's baseline.
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Image(systemName: systemImage ?? tone.defaultSymbol)
                .font(.system(size: 13))
                .foregroundStyle(tone.color)
                .frame(width: DS.Size.rowLeading, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let detail {
                    Text(detail)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                if let footnote {
                    Text(footnote)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .tracking(DS.Tracking.tight)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            // Beside buttons, a title line as tall as they are, so the margins stay even.
            .padding(.vertical, Actions.self == EmptyView.self ? 0 : DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionRow: some View {
        HStack(spacing: DS.Space.xs) {
            actions
        }
    }
}

extension NoticeBanner where Actions == EmptyView {
    public init(tone: Tone, systemImage: String? = nil, title: String, detail: String? = nil, footnote: String? = nil) {
        self.init(tone: tone, systemImage: systemImage, title: title, detail: detail, footnote: footnote) {
            EmptyView()
        }
    }
}

#Preview("Notice banner") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            NoticeBanner(
                tone: .info, title: "You're offline",
                detail: "Your message is queued and sends when the network returns.")
            NoticeBanner(
                tone: .warning, title: "Claude Code sign-in expired",
                detail: "Sign in to keep going; your draft stays put."
            ) {
                Button("Sign In") {}.buttonStyle(.ds(.primary))
            }
            NoticeBanner(tone: .success, title: "Imported your terminal settings") {
                Button("Undo") {}.buttonStyle(.ds(.secondary))
            }
            NoticeBanner(
                tone: .danger, title: "Couldn't restart the background helper",
                detail: "Native is still trying to reconnect."
            ) {
                Button("Show Details") {}.buttonStyle(.ds(.ghost))
                Button("Try Again…") {}.buttonStyle(.ds(.primary))
            }
            .frame(width: 280)
        }
        .frame(width: 520)
    }
}
