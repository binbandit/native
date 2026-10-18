import Foundation

/// A session waiting out a usage limit, and whether the user asked for it to resume at the reset.
struct LimitedSession: Codable, Hashable, Sendable, Identifiable {
    var target: UsageSessionRef
    var work: LimitedWork
    /// When to send `work.resumePrompt`; nil until the user picks "Resume at Reset".
    var resumeAt: Date?

    var id: UsageSessionRef.ID { target.id }
}
