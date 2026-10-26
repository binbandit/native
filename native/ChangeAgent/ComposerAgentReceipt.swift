import SwiftUI

/// The model choice is a section of the existing composer, kept until explicitly dismissed.
struct ComposerAgentReceipt: View {
    let text: String
    var isWorking = false
    var isFailure = false
    var actionTitle: String?
    var actionLabel: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            if isWorking {
                DotGridLoader(pattern: .waiting)
                    .frame(width: DS.ComposerSettings.selectionWidth, height: DS.ComposerSettings.selectionWidth)
            }
            Text(text)
                .foregroundStyle(isFailure ? .dsDanger : .dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .foregroundStyle(.dsTextPrimary)
                    .dsHitTarget(DS.ComposerSettings.controlHeight)
                    .accessibilityLabel(actionLabel ?? actionTitle)
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button("Dismiss Model Change", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .buttonStyle(.plain)
                    .dsHitTarget(DS.ComposerSettings.controlHeight)
            }
        }
        .font(DS.ComposerSettings.rowFont)
        .padding(.horizontal, DS.ComposerQuote.inset)
        .padding(.vertical, DS.Space.sm)
        .frame(minHeight: DS.ComposerSettings.agentReceiptMinHeight)
        .overlay(alignment: .bottom) { SeparatorLine() }
    }
}

#if DEBUG
#Preview("Model choice - Starting, waiting, applied, reversed and failed") {
    DSPreviewPair {
        VStack(spacing: 0) {
            ComposerAgentReceipt(text: "Starting Codex…", isWorking: true, actionTitle: "Cancel", action: {})
            ComposerAgentReceipt(text: "Next model: 6.1 Sol · Codex", actionTitle: "Cancel", action: {})
            ComposerAgentReceipt(text: "Using Codex · 6.1 Sol", actionTitle: "Undo", action: {}, onDismiss: {})
            ComposerAgentReceipt(text: "Using Claude Code · Haiku 5.5", onDismiss: {})
            ComposerAgentReceipt(text: "Using Codex · 6.1 Sol", actionTitle: "Continue with Claude Code", action: {})
            ComposerAgentReceipt(
                text: "Couldn't start Codex. Claude Code is still selected.", isFailure: true,
                actionTitle: "Try Again", action: {}, onDismiss: {})
        }.frame(width: DS.ComposerSettings.width).background(.dsSurface)
    }
}
#endif
