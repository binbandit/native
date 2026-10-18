import ACP
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

// Plugins live on hosts and reach every client (docs/decisions.md). The host sends each plugin's
// manifest as it is on disk, so clients read the fields they know and the host needs no copy of the
// schema; assets travel on request and clients cache them by content hash.

extension HostProtocol.Method {
    public static let listPlugins = "_native/plugins/list"
    public static let pluginAsset = "_native/plugins/asset"
    public static let setPluginEnabled = "_native/plugins/set_enabled"
    /// Host → client: the catalog changed (installed, removed, edited, turned on or off).
    public static let pluginsChanged = "_native/plugins/changed"
}

/// A plugin installed on a host.
public struct HostPlugin: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var version: String?
    public var isEnabled: Bool
    /// The plugin's `plugin.json`, verbatim.
    public var manifest: JSONValue

    public init(id: String, name: String, version: String?, isEnabled: Bool, manifest: JSONValue) {
        self.id = id
        self.name = name
        self.version = version
        self.isEnabled = isEnabled
        self.manifest = manifest
    }
}

public struct PluginsChangedNotification: Codable, Sendable {
    public var plugins: [HostPlugin]

    public init(plugins: [HostPlugin]) {
        self.plugins = plugins
    }
}

public struct SetPluginEnabledParams: Codable, Sendable {
    public var pluginID: String
    public var isEnabled: Bool

    public init(pluginID: String, isEnabled: Bool) {
        self.pluginID = pluginID
        self.isEnabled = isEnabled
    }
}

/// One file from a plugin's folder, such as an icon set image or celebration art.
public struct PluginAssetParams: Codable, Sendable {
    public var pluginID: String
    /// Relative to the plugin's folder; it can't leave it.
    public var path: String
    /// The hash of the copy the client has; the host answers without the data if it's current.
    public var knownHash: String?

    public init(pluginID: String, path: String, knownHash: String? = nil) {
        self.pluginID = pluginID
        self.path = path
        self.knownHash = knownHash
    }
}

public struct PluginAsset: Codable, Sendable {
    public var hash: String
    public var size: Int
    /// Nil when the client's copy (`knownHash`) is current.
    public var data: Data?

    public init(hash: String, size: Int, data: Data?) {
        self.hash = hash
        self.size = size
        self.data = data
    }

    /// Assets travel in one message, so they're capped; plugins keep large media out of their assets.
    public static let sizeLimit = 8 << 20
}

public enum ContentHash {
    /// Lowercase hex SHA-256, the key assets are cached under.
    public static func sha256(_ data: Data) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        #error("Hosts on other platforms need swift-crypto for content hashes")
        #endif
    }
}
