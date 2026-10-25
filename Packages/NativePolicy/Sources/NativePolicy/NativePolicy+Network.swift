import CoreFoundation
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension NativePolicy {
    public enum DeploymentMode: String, Sendable, CaseIterable {
        case ordinary, internalOnly, airGapped
    }

    /// Stable runtime service identifiers. Metadata lives in NativeNetwork.NetworkInventory.
    public enum NetworkService: String, CaseIterable, Sendable, Codable {
        case appUpdateFeed = "updates.app.feed"
        case appUpdateAssets = "updates.app.assets"
        case appUpdateNotes = "updates.app.notes"
        case hostUpdateFeed = "updates.host.feed"
        case hostUpdateSignature = "updates.host.signature"
        case hostUpdateAssets = "updates.host.assets"
        case nativeDiagnostics = "diagnostics.native"
        case organizationDiagnostics = "diagnostics.organization"
        case catalog = "catalog.index"
        case adapters = "adapters.install"
        case components = "components.download"
        case installGuides = "agents.installGuides"
        case agentProvider = "agents.provider"
        case agentIPC = "agents.ipc"
        case mcpHTTP = "mcp.http"
        case mcpProbe = "mcp.probe"
        case mcpSSE = "mcp.sse"
        case mcpStdio = "mcp.stdio"
        case orchestration = "orchestration.loopback"
        case skillsSearch = "skills.search"
        case skillsDownload = "skills.download"
        case skillsGit = "skills.git"
        case iconIndex = "icons.index"
        case iconAssets = "icons.assets"
        case celebrationIndex = "celebrations.index"
        case celebrationSignature = "celebrations.signature"
        case celebrationAssets = "celebrations.assets"
        case git = "git.remote"
        case github = "github.cli"
        case githubAvatar = "github.avatar"
        case remoteConnect = "hosts.connect"
        case remotePair = "hosts.pair"
        case remoteDiscovery = "hosts.discovery"
        case remoteListener = "hosts.listener"
        case localHost = "hosts.localIPC"
        case externalOpen = "external.open"
    }

    public struct Network: Equatable, Sendable {
        public struct Rule: Equatable, Sendable {
            public var enabled: Bool
            /// Exact normalized origins, never patterns. Empty means no approved remote origin.
            public var origins: Set<NetworkOrigin>
            /// Optional primary endpoint (for example, an icon index mirror).
            public var endpoint: URL?

            public init(enabled: Bool, origins: Set<NetworkOrigin> = [], endpoint: URL? = nil) {
                self.enabled = enabled
                self.origins = origins
                self.endpoint = endpoint
            }
        }

        public var mode: DeploymentMode = .ordinary
        public var services: [NetworkService: Rule] = [:]
        /// Explicit local transport switch. Restricted modes default to false.
        public var localIPC = true
        /// A malformed setting poisons the entire network snapshot, including ordinary mode.
        public var isValid = true

        public init() {}
    }
}

/// A syntactically unambiguous origin. Parsing is local and never resolves a hostname.
public struct NetworkOrigin: Hashable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int
    public let isLoopback: Bool

    public init?(url: URL) {
        let raw = url.absoluteString
        guard !raw.contains("\\"), !raw.contains(where: { $0.isWhitespace || $0.isNewline }),
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.user == nil, parts.password == nil, parts.fragment == nil,
            let scheme = parts.scheme?.lowercased(),
            ["https", "http", "ssh", "tcp", "udp"].contains(scheme),
            let rawHost = parts.percentEncodedHost, !rawHost.contains("%"), !rawHost.isEmpty
        else { return nil }
        let authority = raw.dropFirst(scheme.count + 3).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.hasSuffix(":") else { return nil }
        let host = rawHost.lowercased()
        let defaultPort: Int? = ["https": 443, "http": 80, "ssh": 22][scheme]
        guard let port = parts.port ?? defaultPort, (1...65535).contains(port) else { return nil }
        var canonical = host
        var loopback = false
        if host.hasPrefix("[") && host.hasSuffix("]") {
            let literal = String(host.dropFirst().dropLast())
            var address = in6_addr()
            guard inet_pton(AF_INET6, literal, &address) == 1 else { return nil }
            var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &output, socklen_t(output.count)) != nil else { return nil }
            canonical = String(decoding: output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            loopback = canonical == "::1"
        } else {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard !labels.isEmpty, host.count <= 253,
                labels.allSatisfy({ label in
                    !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                        && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                })
            else { return nil }
            // Reject abbreviated, octal, hex and integer IPv4 spellings accepted by some resolvers.
            if labels.last?.allSatisfy({ $0.isNumber }) == true || labels.contains(where: { $0.hasPrefix("0x") }) {
                guard labels.count == 4,
                    labels.allSatisfy({ label in
                        guard let value = UInt8(label) else { return false }
                        return String(value) == label
                    })
                else { return nil }
                loopback = labels.first == "127"
            }
        }
        self.scheme = scheme
        self.host = canonical
        self.port = port
        self.isLoopback = loopback
    }

    /// Policy origins contain no path, query, credentials or fragment.
    public init?(_ string: String) {
        guard let url = URL(string: string), let parts = URLComponents(string: string),
            parts.path.isEmpty || parts.path == "/", parts.query == nil
        else { return nil }
        self.init(url: url)
    }
}

extension PolicyLoader {
    /// Network settings deliberately do not use the legacy fallback-on-invalid resolver.
    static func loadNetwork(from source: any PolicySource, into policy: inout NativePolicy) {
        var network = NativePolicy.Network()
        func value(_ key: PolicyKey) -> Any? {
            if let managed = source.managedValue(forKey: key.rawValue) {
                policy.managedKeys.insert(key)
                return managed
            }
            // A managed deployment/network envelope cannot be loosened through user network keys.
            if source.managedValue(forKey: PolicyKey.deploymentMode.rawValue) != nil
                || source.managedValue(forKey: PolicyKey.network.rawValue) != nil
            {
                return nil
            }
            return source.userValue(forKey: key.rawValue)
        }
        func invalid(_ key: PolicyKey) {
            network.isValid = false
            policy.diagnostics.append(
                PolicyDiagnostic(
                    key: key.rawValue,
                    origin: source.managedValue(forKey: key.rawValue) == nil ? .user : .organization,
                    problem: "invalid network configuration; network denied"))
        }
        if let raw = value(.deploymentMode) {
            if let text = raw as? String, let mode = NativePolicy.DeploymentMode(rawValue: text) {
                network.mode = mode
            } else {
                network.mode = .airGapped
                invalid(.deploymentMode)
            }
        }
        network.localIPC = network.mode == .ordinary
        if let raw = value(.network) {
            if let parsed = parseNetwork(raw, mode: network.mode) {
                network.localIPC = parsed.localIPC
                network.services = parsed.services
            } else {
                invalid(.network)
            }
        }
        if (source.managedKeys ?? []).contains(where: {
            ($0.hasPrefix("policy.network.") || $0.hasPrefix("policy.deployment."))
                && PolicyKey(rawValue: $0) == nil
        }) {
            invalid(.network)
        }
        policy.network = network
    }

    private static func parseNetwork(_ raw: Any, mode: NativePolicy.DeploymentMode) -> NativePolicy.Network? {
        guard let dictionary = raw as? [String: Any], Set(dictionary.keys).isSubset(of: ["localIPC", "services"])
        else { return nil }
        var result = NativePolicy.Network()
        result.mode = mode
        result.localIPC = mode == .ordinary
        if let rawLocal = dictionary["localIPC"] {
            guard let local = networkBool(rawLocal) else { return nil }
            result.localIPC = local
        }
        if let rawServices = dictionary["services"] {
            guard let services = rawServices as? [String: Any] else { return nil }
            for (id, rawRule) in services {
                guard let service = NativePolicy.NetworkService(rawValue: id),
                    let rule = rawRule as? [String: Any],
                    Set(rule.keys).isSubset(of: ["enabled", "origins", "endpoint"]),
                    let rawEnabled = rule["enabled"], let enabled = networkBool(rawEnabled)
                else { return nil }
                var origins = Set<NetworkOrigin>()
                if let rawOrigins = rule["origins"] {
                    guard let strings = rawOrigins as? [String] else { return nil }
                    for string in strings {
                        guard let origin = NetworkOrigin(string) else { return nil }
                        origins.insert(origin)
                    }
                }
                var endpoint: URL?
                if let rawEndpoint = rule["endpoint"] {
                    guard let text = rawEndpoint as? String, let url = URL(string: text),
                        let origin = NetworkOrigin(url: url), origins.contains(origin)
                    else { return nil }
                    endpoint = url
                }
                result.services[service] = .init(enabled: enabled, origins: origins, endpoint: endpoint)
            }
        }
        return result
    }

    private static func networkBool(_ raw: Any) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
