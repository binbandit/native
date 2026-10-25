#if os(macOS)
import Foundation
import IOKit.ps
import NativeHostProtocol

extension PowerState {
    /// Reads this Mac's power sources now.
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
#endif
