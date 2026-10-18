import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The host's own IPv4 addresses, for the QR code: a device tries them when Bonjour can't find the
/// host (another subnet, a VPN). Tailscale's range is labelled so the phone can say how it reached it.
enum LinkInterfaces {
    static func addresses(port: UInt16, includingLoopback: Bool) -> [LinkAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var addresses: [LinkAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                flags & IFF_UP != 0, flags & IFF_RUNNING != 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    == 0
            else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let kind: LinkAddress.Kind
            if flags & IFF_LOOPBACK != 0 {
                guard includingLoopback else { continue }
                kind = .loopback
            } else {
                kind = isTailnet(text) ? .tailnet : .lan
            }
            let entry = LinkAddress(kind: kind, host: text, port: port)
            if !addresses.contains(entry) { addresses.append(entry) }
        }
        // Local networks first: they're the likeliest to answer.
        return addresses.sorted { rank($0.kind) < rank($1.kind) }
    }

    /// 100.64.0.0/10, the carrier-grade NAT range Tailscale assigns from.
    static func isTailnet(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    private static func rank(_ kind: LinkAddress.Kind) -> Int {
        switch kind {
        case .lan: 0
        case .tailnet: 1
        case .loopback: 2
        default: 3
        }
    }
}
