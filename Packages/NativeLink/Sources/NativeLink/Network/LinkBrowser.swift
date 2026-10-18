import Foundation
import Network
import Synchronization

/// A Native host advertising its gateway on this network.
public struct DiscoveredHost: Hashable, Sendable, Identifiable {
    /// The Bonjour service name: the host's machine name, de-duplicated by Bonjour.
    public let name: String
    /// The host key's fingerprint from the TXT record, to match a paired host.
    public let fingerprint: String?
    public let hostID: String?
    public let endpoint: NWEndpoint

    public var id: String { "\(name)|\(fingerprint ?? "")" }
}

/// Watches the local network for Native hosts (`_native-link._tcp`). The phone lists them when
/// pairing by code, and finds a paired host's current address with them.
public final class LinkBrowser: Sendable {
    public let results: AsyncStream<[DiscoveredHost]>
    private let continuation: AsyncStream<[DiscoveredHost]>.Continuation
    private let browser: NWBrowser
    private let latest = Mutex<[DiscoveredHost]>([])

    public init() {
        (results, continuation) = AsyncStream.makeStream(of: [DiscoveredHost].self, bufferingPolicy: .bufferingNewest(1))
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: LinkListener.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [continuation, latest] results, _ in
            let hosts = results.compactMap { result -> DiscoveredHost? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var fingerprint: String?
                var hostID: String?
                if case .bonjour(let record) = result.metadata {
                    fingerprint = record["k"]
                    hostID = record["i"]
                }
                return DiscoveredHost(name: name, fingerprint: fingerprint, hostID: hostID, endpoint: result.endpoint)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            latest.withLock { $0 = hosts }
            continuation.yield(hosts)
        }
        browser.start(queue: DispatchQueue(label: "Native.Link.browser"))
    }

    /// What the browser sees right now.
    public var current: [DiscoveredHost] {
        latest.withLock { $0 }
    }

    public func cancel() {
        browser.cancel()
        continuation.finish()
    }
}
