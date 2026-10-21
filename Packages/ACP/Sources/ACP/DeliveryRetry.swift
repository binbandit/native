import Foundation

/// A message that couldn't reach the agent for a passing reason (the network, a briefly overloaded
/// provider), which Native keeps and sends again by itself after `delay` seconds. It travels with the
/// failure (`SessionState.failTurn(_:retry:at:)`, the host's `turnFailed` event), so every client tells
/// the retry the same way, from the promise to how it turned out.
public struct DeliveryRetry: Codable, Hashable, Sendable {
    public var agentName: String
    /// What went wrong, as the agent put it.
    public var reason: String
    /// Seconds until Native tries again.
    public var delay: Int

    public init(agentName: String, reason: String, delay: Int) {
        self.agentName = agentName
        self.reason = reason
        self.delay = delay
    }

    /// What the transcript says while Native waits to try again.
    public var waitingText: String {
        "\(agentName) couldn't be reached (\(plainReason)). Native kept your message and will try again in "
            + "\(delay) seconds. Use Stop to cancel."
    }

    /// Agents pass their terminal-colored logs along in error messages.
    var plainReason: String {
        reason.withoutTerminalEscapes
    }
}

extension TranscriptNotice {
    /// The notice of a message Native is sending again, and how far that got. One notice follows the
    /// message through every try, so the transcript never holds on to a promise already kept.
    public struct Retry: Hashable, Sendable {
        public enum Progress: Hashable, Sendable {
            /// Native waits, then tries again.
            case waiting
            /// The message went out again.
            case retrying
            /// The agent took it.
            case wentThrough
            /// Native stopped trying: the user stopped it, or another message went first.
            case gaveUp
        }

        public var delivery: DeliveryRetry
        public var progress: Progress

        var text: String {
            switch progress {
            case .waiting: delivery.waitingText
            case .retrying:
                "\(delivery.agentName) couldn't be reached (\(delivery.plainReason)), so Native is trying again."
            case .wentThrough: "Reconnected to \(delivery.agentName), and your message went through on retry."
            case .gaveUp: "\(delivery.agentName) couldn't be reached (\(delivery.plainReason))."
            }
        }

        /// Only an open problem reads as an error; a retry under way or done is just what happened.
        var isError: Bool {
            progress == .waiting || progress == .gaveUp
        }
    }

    init(_ retry: Retry) {
        self.init(text: retry.text, isError: retry.isError, retry: retry)
    }

    /// Says what the retry has come to, in place, so the notice stays the same row.
    mutating func show(_ retry: Retry) {
        text = retry.text
        isError = retry.isError
        self.retry = retry
    }

    /// Becomes the plain failure the retries ended in.
    mutating func show(failure message: String) {
        text = message
        isError = true
        retry = nil
    }
}
