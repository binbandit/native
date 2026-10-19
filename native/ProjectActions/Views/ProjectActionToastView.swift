import SwiftUI

/// How a run ended, as a toast: its tone's glyph, what happened, the command, the next steps, and
/// a dismiss button, on the same surface as the undo toast.
struct ProjectActionToastView: View {
    let toast: ProjectActionToast
    let dismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(toast.message)
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = toast.detail {
                        Text(detail)
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                if !toast.steps.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        ForEach(Array(toast.steps.enumerated()), id: \.offset) { index, step in
                            Button(step.title) {
                                step.perform()
                                dismiss()
                            }
                            .buttonStyle(.ds(index == 0 ? .secondary : .ghost))
                        }
                    }
                }
            }
            Spacer(minLength: DS.Space.md)
            IconButton("Dismiss", systemImage: "xmark", action: dismiss)
        }
        .tracking(DS.Tracking.tight)
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .frame(width: ProjectActionMetrics.toastWidth)
        .dsOverlayBackground(in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch toast.tone {
        case .success: "checkmark.circle"
        case .failure: "exclamationmark.octagon"
        case .info: "info.circle"
        }
    }

    private var color: Color {
        switch toast.tone {
        case .success: .dsSuccess
        case .failure: .dsDanger
        case .info: .dsTextSecondary
        }
    }
}

enum ProjectActionMetrics {
    /// As wide as the undo toast, so the two read as one family.
    static let toastWidth: CGFloat = 356
    static let outputSheetWidth: CGFloat = 640
    static let outputSheetHeight: CGFloat = 420
    static let editorWidth: CGFloat = 480
}

#Preview("Action toasts") {
    DSPreviewPair {
        ProjectActionToastView(
            toast: ProjectActionToast(
                tone: .failure, message: "Format failed with exit code 1 after 2s", detail: "bun run format",
                steps: [.init(title: "Show Output") {}, .init(title: "Run in Terminal") {}]),
            dismiss: {})
        ProjectActionToastView(
            toast: ProjectActionToast(
                tone: .success, message: "Install finished in 14s", detail: "bun install",
                steps: [.init(title: "Show Output") {}]),
            dismiss: {})
    }
}
