import Foundation
import NativeHostProtocol

/// A host's plugin assets on this device: fetched once, kept by content hash, and served from disk
/// when the host can't be reached. One per host, in a folder of its own.
public actor PluginAssets {
    private let client: NativeHostClient
    private let directory: URL
    /// The hash last seen for each "<plugin id>/<path>".
    private var index: [String: String]

    public init(client: NativeHostClient, directory: URL) {
        self.client = client
        self.directory = directory
        index =
            (try? JSONDecoder().decode(
                [String: String].self, from: Data(contentsOf: directory.appending(path: "index.json"))))
            ?? [:]
    }

    /// The file's contents: the host's current copy when connected (re-downloaded only if it
    /// changed), otherwise the last copy fetched.
    public func data(pluginID: String, path: String) async throws -> Data {
        let key = "\(pluginID)/\(path)"
        let known = index[key]
        do {
            let asset = try await client.pluginAsset(
                PluginAssetParams(pluginID: pluginID, path: path, knownHash: known))
            if let data = asset.data {
                guard ContentHash.sha256(data) == asset.hash else { throw CacheError.corrupt(path) }
                try store(data, hash: asset.hash, for: key)
                return data
            }
            if let cached = cached(asset.hash) { return cached }
            // The copy we had is gone from disk; ask for the data again.
            index[key] = nil
            return try await data(pluginID: pluginID, path: path)
        } catch NativeHostClient.Failure.notConnected {
            guard let known, let cached = cached(known) else { throw NativeHostClient.Failure.notConnected }
            return cached
        }
    }

    public enum CacheError: Error, LocalizedError {
        case corrupt(String)

        public var errorDescription: String? {
            switch self {
            case .corrupt(let path): "\(path) arrived damaged; try again."
            }
        }
    }

    private func cached(_ hash: String) -> Data? {
        try? Data(contentsOf: blob(hash))
    }

    private func store(_ data: Data, hash: String, for key: String) throws {
        try FileManager.default.createDirectory(
            at: directory.appending(path: "blobs"), withIntermediateDirectories: true)
        try data.write(to: blob(hash), options: .atomic)
        index[key] = hash
        try JSONEncoder().encode(index).write(to: directory.appending(path: "index.json"), options: .atomic)
    }

    private func blob(_ hash: String) -> URL {
        directory.appending(path: "blobs/\(hash)")
    }
}
