import ACP
import Foundation

extension TurnOutcome {
    /// The outcome of a `session/prompt`: its stop reason, or the error it failed with.
    init(stopReason: StopReason?, error: (any Error)?) {
        switch stopReason {
        case .endTurn: self = .ended
        case .cancelled: self = .cancelled
        case .maxTokens: self = .limited("The response hit the token limit")
        case .maxTurnRequests: self = .limited("The turn hit its request limit")
        case .refusal: self = .refused
        case .error: self = .failed("The turn failed")
        case .other(let reason): self = .failed(reason)
        case nil: self = .failure(error?.localizedDescription ?? "The turn didn't finish")
        }
    }
}
