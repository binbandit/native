import Foundation

/// Evidence from the failed turn only; older failures and recoveries must not describe a new one.
public struct TurnFailureContext: Equatable, Sendable {
    public let details: String?
    public let recovery: String?

    public init(state: SessionState) {
        guard let turn = state.turns.last else {
            details = nil
            recovery = nil
            return
        }
        let notices = state.items[turn.items].compactMap { item -> TranscriptNotice? in
            if case .notice(let notice) = item { return notice }
            return nil
        }
        details = notices.last(where: \.isError)?.text
        recovery = notices.last { $0.sentToAgent != nil || $0.retry?.progress == .wentThrough }?.text
    }
}
