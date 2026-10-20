import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What the host says about its machine in `HostStatus`, read by the platform layer
/// (`NativeHostMac.MacHost.systemInfo()`). A host without one says what Foundation knows.
public struct HostSystemInfo: Sendable {
    /// "macOS 27.1", later "Ubuntu 24.04".
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
        HostSystemInfo(system: ProcessInfo.processInfo.operatingSystemVersionString, model: nil)
    }

    /// `getloadavg(3)`, which Darwin and glibc both have.
    @Sendable
    public static func oneMinuteLoad() -> Double? {
        var loads = [Double](repeating: 0, count: 1)
        return getloadavg(&loads, 1) == 1 ? loads[0] : nil
    }
}
