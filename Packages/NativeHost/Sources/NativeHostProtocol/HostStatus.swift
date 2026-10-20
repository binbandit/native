import Foundation

// How a host's machine is doing, for the hosts list and the status bar: what it runs on, since when,
// how loaded it is, and whether it's being kept awake. Clients get it on request and then as
// `changed`, about every 30 seconds while connected and at once when keeping awake changes.

extension HostProtocol.Method {
    /// → `HostStatus`.
    public static let hostStatus = "_native/host/status"
    /// Host → clients: `{status}`.
    public static let hostStatusChanged = "_native/host/status/changed"
}

public struct HostStatus: Codable, Hashable, Sendable {
    /// The operating system and its version: "macOS 27.1", later "Ubuntu 24.04".
    public var system: String
    /// The hardware's model identifier ("Mac16,10"), where the platform has one.
    public var model: String?
    public var bootedAt: Date?
    /// The 1-minute load average.
    public var loadAverage: Double?
    public var keepAwake: HostKeepAwakeState
    public var checkedAt: Date

    public init(
        system: String, model: String?, bootedAt: Date?, loadAverage: Double?, keepAwake: HostKeepAwakeState,
        checkedAt: Date
    ) {
        self.system = system
        self.model = model
        self.bootedAt = bootedAt
        self.loadAverage = loadAverage
        self.keepAwake = keepAwake
        self.checkedAt = checkedAt
    }
}

public struct HostStatusChangedNotification: Codable, Sendable {
    public var status: HostStatus

    public init(status: HostStatus) {
        self.status = status
    }
}
