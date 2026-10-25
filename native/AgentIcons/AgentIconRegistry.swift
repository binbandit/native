import CryptoKit
import Foundation
import NativeNetwork
import NativePolicy

/// Agent icons from the official ACP registry, fetched at runtime and cached in Application
/// Support, so Native ships no other product's artwork and works offline once it has seen them.
///
/// The registry is one JSON index (`agents[].id` and `agents[].icon`, a 16×16 monochrome SVG URL).
/// A cached icon is used as is and refreshed in the background once it's a week old; the index is
/// fetched only when an icon isn't cached, at most once a day.
actor AgentIconRegistry {
    static let indexURL = NetworkInventory.iconIndexURL

    private struct Index: Decodable {
        struct Agent: Decodable {
            let id: String
            let icon: URL?
        }

        let agents: [Agent]
    }

    private let directory: URL
    private let network: NetworkClient
    private var index: Task<Index?, Never>?
    private var indexRevision: UInt64?

    private static let iconLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let indexLifetime: TimeInterval = 24 * 60 * 60
    /// Registry icons are a few kilobytes; anything far bigger isn't one.
    private static let maximumIconSize = 256 * 1024

    static var defaultDirectory: URL {
        let folder = Bundle.main.bundleIdentifier ?? "Native"
        return URL.applicationSupportDirectory.appending(path: "\(folder)/AgentIcons", directoryHint: .isDirectory)
    }

    init(directory: URL = AgentIconRegistry.defaultDirectory, network: NetworkClient? = nil) {
        self.directory = directory
        let source = PolicyCenter.platformSource()
        self.network =
            network
            ?? NetworkClient(
                policy: { PolicyLoader.load(from: source) }, updates: PolicyLoader.updates(from: source))
    }

    /// Preserve inert preview protocol configuration, while still prohibiting automatic redirects.
    init(directory: URL = AgentIconRegistry.defaultDirectory, session: URLSession) {
        self.directory = directory
        let source = PolicyCenter.platformSource()
        self.network = NetworkClient(
            policy: { PolicyLoader.load(from: source) }, updates: PolicyLoader.updates(from: source),
            transport: URLSessionNetworkTransport(configuration: session.configuration))
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
        do {
            try network.checkService(.iconAssets)
            let revision = network.policyRevision
            guard let url = await iconURL(for: id), revision == network.policyRevision else { return nil }
            let receipt = try await network.get(service: .iconAssets, url: url)
            let data = receipt.response.data
            guard receipt.response.status == 200, data.count < Self.maximumIconSize,
                AgentIconGlyph(svg: data) != nil
            else { return nil }
            return try network.publish(receipt) {
                try write(data, to: iconFile(for: id))
                return data
            }
        } catch {
            return nil
        }
    }

    private func iconURL(for id: String) async -> URL? {
        let revision = network.policyRevision
        if index == nil || indexRevision != revision {
            index?.cancel()
            indexRevision = revision
            index = Task { await loadIndex() }
        }
        return await index?.value?.agents.first { $0.id == id }?.icon
    }

    /// The cached index while it's fresh, otherwise a new one (kept for the next launch), falling
    /// back to the stale copy when offline.
    private func loadIndex() async -> Index? {
        guard let url = network.endpoint(for: .iconIndex, default: Self.indexURL) else { return nil }
        // A new mirror must never fall back to URLs retained from a different index source.
        let filename: String
        if url == Self.indexURL {
            filename = "registry.json"
        } else {
            let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            filename = "registry-\(digest).json"
        }
        let file = directory.appending(path: filename)
        let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
        if let cached, Self.age(of: file) < Self.indexLifetime { return cached }
        do {
            let receipt = try await network.get(service: .iconIndex, url: url)
            let data = receipt.response.data
            guard receipt.response.status == 200 else { return cached }
            let index = try JSONDecoder().decode(Index.self, from: data)
            return try network.publish(receipt) {
                try write(data, to: file)
                return index
            }
        } catch {
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
