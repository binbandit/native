import ACP
import Foundation
import NativePolicy

extension SessionModel {
    func enforceDiffCommentRetention() {
        guard !diffCommentRetentionAllowed else { return }
        diffCommentEditors = []
        activeDiffComment = nil
        unresolvedCommentPacket = nil
        let current = PromptQuote.split(draft)
        draft = PromptQuote.draft(quotes: current.quotes.filter { $0.side == .transcript }, message: current.message)
    }

    var diffCommentRetentionAllowed: Bool { diffCommentsPolicy().sourceExcerptsRetentionEnabled }

    var diffCommentSendBlock: String? {
        if diffCommentSending { return "Checking whether your comments arrived…" }
        if unresolvedCommentPacket != nil { return "Delivery is unresolved. Check the transcript before resending." }
        return sourceExcerptBlock(for: draft)
    }

    func sourceExcerptBlock(for text: String) -> String? {
        guard !diffCommentsPolicy().sourceExcerptsSendingEnabled,
            PromptQuote.split(text).quotes.contains(where: { $0.side != .transcript })
        else { return nil }
        return "Comments can’t be sent from this project."
    }

    var diffCommentManagedExplanation: String {
        let policy = diffCommentsPolicy()
        return policy.organizationName.map { "Managed by \($0)." } ?? PolicyCenter.managedExplanation
    }
}
