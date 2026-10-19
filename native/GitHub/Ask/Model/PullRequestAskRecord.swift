import Foundation
import GitHub

/// A pull request's private conversation, remembered across launches so reopening the panel shows
/// it again: which agent session holds it, the folder it runs in, and what its context described.
struct PullRequestAskRecord: Codable, Hashable {
    let key: SessionKey
    let folder: URL
    /// The head commit the agent's context describes; newer commits refresh it on the next question.
    var headRefOid: String
    /// What the context carried, for the panel's context line.
    var inclusion: PullRequestAskInclusion
    let startedAt: Date
}

/// Every pull request's current conversation, in the user defaults. A conversation the user started
/// over from stays in the agent's history (and search); only this pointer to it goes.
struct PullRequestAskRecords {
    private struct Entry: Codable {
        let reference: PullRequestReference
        let record: PullRequestAskRecord
    }

    private(set) var all: [PullRequestReference: PullRequestAskRecord]
    private let defaults: UserDefaults
    private static let key = "pullRequestQuestions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let entries =
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        all = Dictionary(entries.map { ($0.reference, $0.record) }, uniquingKeysWith: { _, last in last })
    }

    subscript(reference: PullRequestReference) -> PullRequestAskRecord? {
        get { all[reference] }
        set {
            all[reference] = newValue
            save()
        }
    }

    /// The pull request a session belongs to, for opening one that search found.
    func reference(of key: SessionKey) -> PullRequestReference? {
        all.first { $0.value.key == key }?.key
    }

    private func save() {
        let entries = all.map { Entry(reference: $0.key, record: $0.value) }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
