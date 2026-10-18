import Foundation
import os

/// Where `ActivityLog` keeps its days.
protocol ActivityStore {
    func load() -> [ActivityDay]
    func save(_ days: [ActivityDay])
}

/// A JSON file in the host's Application Support folder, next to the usage limits.
struct ActivityFileStore: ActivityStore {
    let url: URL

    init(url: URL = UsageLimitsFileStore.defaultURL.deletingLastPathComponent().appending(path: "usage-activity.json")) {
        self.url = url
    }

    func load() -> [ActivityDay] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ActivityDay].self, from: data)) ?? []
    }

    func save(_ days: [ActivityDay]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(days).write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "Native", category: "Usage").error("Couldn't save activity: \(error)")
        }
    }
}

/// A session an agent lists, for filling in days from before Native recorded them.
struct ActivityBackfill: Hashable {
    let agent: String
    let agentName: String
    let session: String
    let title: String?
    let project: String
    let updatedAt: Date
}
