import Foundation
import os

/// Agent icons from the official ACP registry, fetched at runtime and cached in Application
/// Support, so Native ships no other product's artwork and works offline once it has seen them.
///
/// The registry is one JSON index (`agents[].id` and `agents[].icon`, a 16×16 monochrome SVG URL).
/// A cached icon is used as is and refreshed in the background once it's a week old; the index is
/// fetched only when an icon isn't cached, at most once a day.
actor AgentIconRegistry {
    static let indexURL = URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")

    private struct Index: Decodable {
        struct Agent: Decodable {
            let id: String
            let icon: URL?
        }

        let agents: [Agent]
    }

    private let directory: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "Native", category: "AgentIcons")
    private var index: Task<Index?, Never>?

    private static let iconLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let indexLifetime: TimeInterval = 24 * 60 * 60
    /// Registry icons are a few kilobytes; anything far bigger isn't one.
    private static let maximumIconSize = 256 * 1024

    static var defaultDirectory: URL {
        let folder = Bundle.main.bundleIdentifier ?? "Native"
        return URL.applicationSupportDirectory.appending(path: "\(folder)/AgentIcons", directoryHint: .isDirectory)
    }

    init(directory: URL = AgentIconRegistry.defaultDirectory, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    /// The SVG for the agent with this registry id: cached if there is a copy, fetched if not. Nil
    /// when it's in neither place (offline on first use, or not in the registry).
    func icon(for id: String) async -> Data? {
        let file = iconFile(for: id)
        if let cached = try? Data(contentsOf: file) {
            if Self.age(of: file) > Self.iconLifetime {
                Task { await self.refresh(id) }
            }
            return cached
        }
        return await refresh(id)
    }

    /// Fetches the icon again and replaces the cached copy if the new one is valid.
    @discardableResult
    private func refresh(_ id: String) async -> Data? {
        guard let url = await iconURL(for: id) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < Self.maximumIconSize,
                AgentIconGlyph(svg: data) != nil
            else { return nil }
            try write(data, to: iconFile(for: id))
            return data
        } catch {
            logger.info("Couldn't fetch the registry icon for \(id, privacy: .public): \(error)")
            return nil
        }
    }

    private func iconURL(for id: String) async -> URL? {
        if index == nil {
            index = Task { await loadIndex() }
        }
        return await index?.value?.agents.first { $0.id == id }?.icon
    }

    /// The cached index while it's fresh, otherwise a new one (kept for the next launch), falling
    /// back to the stale copy when offline.
    private func loadIndex() async -> Index? {
        let file = directory.appending(path: "registry.json")
        let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
        if let cached, Self.age(of: file) < Self.indexLifetime { return cached }
        guard let url = Self.indexURL else { return cached }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return cached }
            let index = try JSONDecoder().decode(Index.self, from: data)
            try write(data, to: file)
            return index
        } catch {
            logger.info("Couldn't fetch the ACP registry: \(error)")
            return cached
        }
    }

    private func iconFile(for id: String) -> URL {
        // Registry ids are slugs; anything else can't name a file outside the cache.
        let name = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        return directory.appending(path: "icons/\(name).svg")
    }

    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    private static func age(of file: URL) -> TimeInterval {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return modified.map { Date.now.timeIntervalSince($0) } ?? .infinity
    }
}
