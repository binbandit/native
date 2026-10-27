import SwiftUI

struct ComposerAgentReceiptSection: View {
    let change: ComposerAgentChange
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if !change.isReceiptDismissed, change.stage != .cancelled {
            ComposerAgentReceipt(
                text: change.receipt, isWorking: change.stage == .preparing && change.showsLoader,
                isFailure: change.stage == .failed, actionTitle: actionTitle,
                actionLabel: change.canUndo ? "Undo Change to \(change.choice.agentName)" : nil,
                action: receiptAction,
                onDismiss: dismissAction)
        }
    }

    private var receiptAction: (() -> Void)? {
        guard actionTitle != nil else { return nil }
        return { perform() }
    }

    private var dismissAction: (() -> Void)? {
        guard !change.isPending else { return nil }
        return { change.isReceiptDismissed = true }
    }

    private var actionTitle: String? {
        if change.isPending { return "Cancel" }
        if change.canUndo { return "Undo" }
        if change.stage == .failed { return "Try Again" }
        if change.stage == .applied { return "Continue with \(change.sourceName)" }
        return nil
    }

    private func perform() {
        if change.isPending {
            change.cancel()
        } else if change.canUndo {
            change.undo()
        } else if change.stage == .failed {
            change.retry(undoManager: undoManager)
        } else {
            change.continueWithSource()
        }
    }
}

#if DEBUG
#Preview("Model choice - Receipt section") {
    DSPreviewPair { ComposerAgentReceipt(text: "Using Codex · 6.1 Sol", actionTitle: "Undo", action: {}) }
}
#endif
