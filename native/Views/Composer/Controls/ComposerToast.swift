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
            // The glyph and Undo sit on the message's first baseline, as in every undo toast.
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(message)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(2)
                if let onUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.ds(.secondary))
                        .help("Undo (⌘Z)")
                }
            }
            .font(.dsBody)
            .padding(.horizontal, DS.Space.md)
            // The 24pt Undo button sets the height, so the toast stays as compact as a plain one.
            .padding(.vertical, onUndo == nil ? DS.Space.sm : DS.Space.xs)
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
