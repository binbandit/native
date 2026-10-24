import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What the host says about its machine in `HostStatus`, read by the platform layer
/// (`NativeHostMac.MacHost.systemInfo()`). Other hosts use os-release on Linux or Foundation.
public struct HostSystemInfo: Sendable {
    /// "macOS 27.1" or "Ubuntu 24.04 LTS".
    public var system: String
    /// The hardware's model identifier ("Mac16,10"), where there is one.
    public var model: String?
    /// The 1-minute load average, read each time status is sent.
    public var loadAverage: @Sendable () -> Double?

    public init(system: String, model: String?, loadAverage: @escaping @Sendable () -> Double? = Self.oneMinuteLoad) {
        self.system = system
        self.model = model
        self.loadAverage = loadAverage
    }

    public static var portable: HostSystemInfo {
        #if os(Linux)
        HostSystemInfo(system: HostLinuxReleaseInfo.systemName(), model: nil)
        #else
        HostSystemInfo(system: ProcessInfo.processInfo.operatingSystemVersionString, model: nil)
        #endif
    }

    /// `getloadavg(3)`, which Darwin and glibc both have.
    @Sendable
    public static func oneMinuteLoad() -> Double? {
        var loads = [Double](repeating: 0, count: 1)
        return getloadavg(&loads, 1) == 1 ? loads[0] : nil
    }
}
