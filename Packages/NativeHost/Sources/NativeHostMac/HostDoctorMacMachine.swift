import Darwin
import Exec
import Foundation
import NativeHost

/// The doctor's view of this Mac: commands run with `Exec`, the rest asked of the system. Reads only.
public struct HostDoctorMacMachine: HostDoctorMachine {
    /// Long enough for a CLI that loads a lot to print its version; short enough that one that hangs
    /// doesn't hold up the report.
    static let commandTimeout = Duration.seconds(10)

    public init() {}

    public var userName: String {
        NSUserName()
    }

    public var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    }

    public func isExecutableFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    public func run(
        _ executable: String, _ arguments: [String], environment: [String: String]
    ) async
        -> HostDoctorOutput?
    {
        let command = Command(
            executable, arguments, environment: environment, standardInput: Data(), timeout: Self.commandTimeout)
        guard let result = try? await LocalCommandRunner().run(command) else { return nil }
        return HostDoctorOutput(status: result.exitCode, output: result.output, errorOutput: result.errorOutput)
    }

    public func availableSpace(at path: String) -> Int64? {
        let values = try? URL(filePath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func networkAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var addresses: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    == 0
            else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !addresses.contains(text) { addresses.append(text) }
        }
        return addresses
    }

    /// A TCP connect to 127.0.0.1, closed at once: refused quickly when nothing listens.
    public func acceptsConnections(onPort port: UInt16) async -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
