import ACP
import Foundation

extension SessionModel {
    var canRetryHomeNext: Bool {
        taskStatus == .failed && acceptsPrompts && (host != nil || phase == .idle)
    }

    /// Ask it to check completed work before continuing, without replacing the user's draft.
    func retryHomeNext(turnID: String?) async throws {
        guard canRetryHomeNext, state.turns.last?.id == turnID else { throw SendError.busy }
        try await submit(
            "Continue the interrupted task from where it stopped. Check what already completed before repeating any work.",
            .queue)
    }
}
