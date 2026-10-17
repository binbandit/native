import Foundation
import os

/// Where `UsageLimits` keeps its snapshot.
protocol UsageLimitsStore {
    func load() -> UsageLimitsSnapshot
    func save(_ snapshot: UsageLimitsSnapshot)
}

/// A JSON file in Application Support, which `docs/architecture.md` reserves for durable state a
/// feature owns.
struct UsageLimitsFileStore: UsageLimitsStore {
    let url: URL

    static var defaultURL: URL {
        let folder = Bundle.main.bundleIdentifier ?? "Native"
        return URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory).appending(
            path: "usage-limits.json")
    }

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    func load() -> UsageLimitsSnapshot {
        guard let data = try? Data(contentsOf: url) else { return UsageLimitsSnapshot() }
        do {
            return try JSONDecoder().decode(UsageLimitsSnapshot.self, from: data)
        } catch {
            // A file from an incompatible build only holds stale reminders; starting over is fine.
            Logger(subsystem: "Native", category: "Usage").error("Ignoring unreadable usage limits: \(error)")
            return UsageLimitsSnapshot()
        }
    }

    func save(_ snapshot: UsageLimitsSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "Native", category: "Usage").error("Couldn't save usage limits: \(error)")
        }
    }
}
