import Foundation
import IOKit.ps

/// Whether the Mac runs on battery, and how charged it is.
nonisolated struct PowerState: Hashable, Sendable {
    var isOnBattery = false
    /// 0...1, or nil for Macs without a battery.
    var batteryLevel: Double?

    /// Reads the power sources now.
    static func current() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return PowerState() }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var state = PowerState(isOnBattery: providing == kIOPSBatteryPowerValue)
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            state.batteryLevel = Double(current) / Double(maximum)
        }
        return state
    }
}
