import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The host's own IPv4 addresses, for the QR code: a device tries them when Bonjour can't find the
/// host (another subnet, a VPN). Tailscale's range is labelled so the phone can say how it reached it,
/// and its MagicDNS name follows its address, since the name outlives the address.
enum LinkInterfaces {
    /// `tailnetNames` maps a Tailscale address to its name (`resolveTailnetNames`).
    static func addresses(port: UInt16, includingLoopback: Bool, tailnetNames: [String: String] = [:]) -> [LinkAddress]
    {
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
            for host in [text, kind == .tailnet ? tailnetNames[text] : nil].compactMap(\.self) {
                let entry = LinkAddress(kind: kind, host: host, port: port)
                if !addresses.contains(entry) { addresses.append(entry) }
            }
        }
        // Local networks first: they're the likeliest to answer.
        return addresses.sorted { rank($0.kind) < rank($1.kind) }
    }

    /// The names Tailscale's resolver gives `addresses` (`mac-mini.tail1234.ts.net`), by reverse
    /// lookup, so nothing else needs to be installed or run. Lookups still going after `timeout` are
    /// left out; one that fails (no MagicDNS) just has no name.
    static func resolveTailnetNames(_ addresses: [String], timeout: Duration) async -> [String: String] {
        await withTaskGroup(of: (String, String?)?.self) { group in
            for address in addresses {
                group.addTask {
                    // getnameinfo blocks and can't be cancelled, so it runs on a thread of its own.
                    await withCheckedContinuation { continuation in
                        Thread.detachNewThread { continuation.resume(returning: (address, reverseName(of: address))) }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            var names: [String: String] = [:]
            var pending = addresses.count
            while pending > 0, let result = await group.next() {
                guard let (address, name) = result else { break }
                pending -= 1
                if let name { names[address] = name }
            }
            group.cancelAll()
            return names
        }
    }

    private static func reverseName(of address: String) -> String? {
        var socket = sockaddr_in()
        socket.sin_family = sa_family_t(AF_INET)
        #if canImport(Darwin)
        socket.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        guard inet_pton(AF_INET, address, &socket.sin_addr) == 1 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &socket) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo(
                    $0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard status == 0 else { return nil }
        var name = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty || name == address ? nil : name
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
