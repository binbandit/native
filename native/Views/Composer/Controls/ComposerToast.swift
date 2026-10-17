import SwiftUI

/// What the last action did, or why sending is blocked, floating just above the composer's top
/// edge so it doesn't move the transcript or crowd the controls.
struct ComposerToast: View {
    let message: String
    let tone: ComposerFeedback.Tone
    /// Offered for actions that can be taken back; ⌘Z does the same.
    var onUndo: (() -> Void)?

    var body: some View {
        ComposerSurface(isFloating: true) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(message)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(2)
                if let onUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.plain)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsAccentText)
                        .help("Undo (⌘Z)")
                }
            }
            .font(.dsBody)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var symbol: String {
        switch tone {
        case .done: "checkmark.circle"
        case .notice: "info.circle"
        case .problem: "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .done: .dsSuccess
        case .notice: .dsTextSecondary
        case .problem: .dsWarning
        }
    }
}
