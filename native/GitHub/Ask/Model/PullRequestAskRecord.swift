import Foundation
import GitHub

/// A pull request's private conversation, remembered across launches so reopening the panel shows
/// it again: which agent session holds it, the folder it runs in, and what its context described.
struct PullRequestAskRecord: Codable, Hashable {
    let key: SessionKey
    let folder: URL
    /// The head commit the agent's context describes; newer commits refresh it on the next
    /// question. Empty when that isn't known (a conversation found by its folder alone).
    var headRefOid: String
    /// What the context carried, for the panel's context line; nil when that isn't known.
    var inclusion: PullRequestAskInclusion?
    let startedAt: Date
}

/// Every pull request's conversations, in the user defaults: the current one per pull request, and
/// the ones the user started over from, so search can open those on their pull request too. The
/// conversations themselves stay in the agent's history.
struct PullRequestAskRecords {
    private struct Entry: Codable {
        let reference: PullRequestReference
        let record: PullRequestAskRecord
    }

    private struct Stored: Codable {
        var current: [Entry] = []
        var earlier: [Entry] = []
    }

    private(set) var current: [PullRequestReference: PullRequestAskRecord]
    /// Conversations started over from, newest last, by session.
    private var earlier: [SessionKey: Entry]
    private let defaults: UserDefaults
    private static let key = "pullRequestQuestions"
    /// Enough to find any recent one again; older ones open from their folder's name alone.
    private static let earlierLimit = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        current = Dictionary(
            (stored?.current ?? []).map { ($0.reference, $0.record) }, uniquingKeysWith: { _, last in last })
        earlier = Dictionary((stored?.earlier ?? []).map { ($0.record.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    subscript(reference: PullRequestReference) -> PullRequestAskRecord? {
        current[reference]
    }

    /// Makes `record` the pull request's conversation, keeping the one it replaces as an earlier one.
    mutating func setCurrent(_ record: PullRequestAskRecord?, for reference: PullRequestReference) {
        if let replaced = current[reference], replaced.key != record?.key {
            earlier[replaced.key] = Entry(reference: reference, record: replaced)
        }
        if let record { earlier[record.key] = nil }
        current[reference] = record
        save()
    }

    /// The pull request a session belongs to and its record, current or earlier.
    func find(_ key: SessionKey) -> (reference: PullRequestReference, record: PullRequestAskRecord)? {
        if let match = current.first(where: { $0.value.key == key }) { return (match.key, match.value) }
        return earlier[key].map { ($0.reference, $0.record) }
    }

    private func save() {
        let kept = earlier.values.sorted { $0.record.startedAt < $1.record.startedAt }.suffix(Self.earlierLimit)
        let stored = Stored(
            current: current.map { Entry(reference: $0.key, record: $0.value) }, earlier: Array(kept))
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
