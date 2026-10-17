import ACP
import Foundation

/// Whether and when to send a failed prompt again: only when the failure looks like the network or
/// the provider being briefly unavailable and the agent got nowhere, a few times, further apart
/// each time. Usage limits and sign-in problems are someone else's to handle.
nonisolated struct TurnRetryPolicy: Equatable, Sendable {
    static let delays: [Duration] = [.seconds(5), .seconds(20), .seconds(60)]

    private(set) var attempts = 0

    /// The wait before the next try, or nil to stop trying. Counts the try when it returns one.
    mutating func nextDelay(after error: any Error, turnMadeProgress: Bool) -> Duration? {
        guard !turnMadeProgress, Self.isTransient(error), attempts < Self.delays.count else { return nil }
        defer { attempts += 1 }
        return Self.delays[attempts]
    }

    mutating func reset() {
        attempts = 0
    }

    static func isTransient(_ error: any Error) -> Bool {
        if (error as? RPCError)?.isAuthRequired == true || UsageLimitHit(error: error) != nil {
            return false
        }
        if error is URLError {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return transientMarkers.contains { text.contains($0) }
    }

    /// How agents word network and provider outages in the errors they pass on.
    private static let transientMarkers = [
        "network", "connection error", "connection refused", "connection reset", "timed out", "timeout",
        "econnreset", "econnrefused", "enotfound", "eai_again", "socket hang up", "fetch failed",
        "overloaded", "service unavailable", "bad gateway", "temporarily unavailable", " 502", " 503", " 529",
    ]
}
