import SwiftUI

/// A workflow step waiting at its gate, in the same shape as a tool's permission request: what's
/// about to happen, the exact prompt it will run with (editable), and Approve or Reject on the same
/// keys. Only the oldest pending request in view answers the keys (`answersShortcuts`).
struct WorkflowApprovalCard: View {
    let step: WorkflowStepRun
    var answersShortcuts = true
    let onApprove: (_ editedPrompt: String?) -> Void
    let onSkip: () -> Void
    let onReject: () -> Void

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(question)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let message = step.step.approval?.message {
                    Text(message)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tracking(DS.Tracking.tight)
            promptView
            buttons
        }
        .padding(DS.Space.lg)
        // Amber like every request that waits on the user, whatever the accent theme.
        .background(Color.dsAttention.opacity(0.06), in: shape)
        .overlay { shape.strokeBorder(Color.dsAttention.opacity(0.45), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question)
    }

    private var question: String {
        if step.step.kind == .pullRequest {
            return "Open the pull request?"
        }
        return "Run \u{201C}\(step.step.title)\u{201D}" + (step.assignment.agent.map { " on \($0.name)" } ?? "") + "?"
    }

    @ViewBuilder private var promptView: some View {
        if isEditing {
            AutomationTextField(label: "Prompt", text: $draft, axis: .vertical, lines: 4...14, font: .dsMonoCaption)
        } else {
            CappedHeightScrollView(maxHeight: 160) {
                Text(step.prompt ?? "")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.md)
            }
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control))
        }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) {
                actionButtons
                Spacer(minLength: DS.Space.lg)
                shortcutHint
            }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.md) { actionButtons }
                shortcutHint
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button(isEditing ? "Approve Edited" : "Approve") {
            onApprove(isEditing ? draft : nil)
        }
        .buttonStyle(.ds(.primary))
        .keyboardShortcut(answersShortcuts ? KeyboardShortcut("y", modifiers: .command) : nil)
        Button(isEditing ? "Discard Edits" : "Edit Prompt") {
            if !isEditing {
                draft = step.prompt ?? ""
            }
            withAnimation(.dsStandard) { isEditing.toggle() }
        }
        .buttonStyle(.ds(.secondary))
        Button("Skip Step", action: onSkip)
            .buttonStyle(.ds(.ghost))
            .help("Leave this step out; the steps after it run without its result")
        Button("Reject", role: .destructive, action: onReject)
            .buttonStyle(.ds(.ghost))
            .keyboardShortcut(answersShortcuts ? KeyboardShortcut(.delete, modifiers: [.command, .shift]) : nil)
            .help("Stop the workflow here")
    }

    @ViewBuilder private var shortcutHint: some View {
        if answersShortcuts {
            Text("⌘Y Approve  ·  ⌘⇧⌫ Reject")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
