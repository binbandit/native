import ACP
import Foundation

/// Where a usage limit stopped a turn, read from what the turn left at its end: the agent relaying
/// the provider's message, Native's notice that the turn failed, or both. The transcript shows one
/// card in their place.
struct UsageLimitStop: Hashable {
    /// The provider's own words.
    let message: String
    /// Every item that reports the limit; the card stands in for them all.
    let itemIDs: Set<String>
    /// Where the card goes: the last of them.
    let anchorID: String

    /// Nil unless the turn ended on a limit. An agent's message alone counts only when it reads
    /// exactly like a provider's (a known prefix and a reset time) or the turn failed, so prose
    /// that happens to start "You've reached your" stays prose.
    init?(turnItems items: some BidirectionalCollection<TranscriptItem>, stopReason: StopReason?) {
        var reports: [(id: String, text: String, isNotice: Bool)] = []
        for item in items.reversed() {
            switch item {
            case .notice(let notice):
                if UsageLimitHit.isLimitMessage(notice.text) {
                    reports.append((item.id, notice.text, true))
                }
                continue
            case .message(let message) where message.role == .agent:
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if UsageLimitHit.isLimitMessage(text) {
                    reports.append((item.id, text, false))
                    continue
                }
            default:
                break
            }
            break
        }
        guard let anchor = reports.first else { return nil }
        let isTrusted = stopReason == .error || reports.contains { report in
            report.isNotice || UsageLimitHit(text: report.text).map { $0.resetsAt != nil || $0.window != nil } == true
        }
        guard isTrusted else { return nil }
        // The agent's relay keeps the provider's exact words; Native's notice may be a copy.
        message = reports.last { !$0.isNotice }?.text ?? anchor.text
        itemIDs = Set(reports.map(\.id))
        anchorID = anchor.id
    }
}
