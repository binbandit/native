import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import NativeHost
import NativeHostProtocol
import Synchronization
import notify

/// The Mac's power assertions, the ones `caffeinate` takes, held by the host process. Releasing on
/// deinit, and the system releasing a dead process's assertions, mean the Mac is never left awake by
/// mistake, however the host ends.
public final class MacPowerBackend: HostPowerBackend {
    private let held = Mutex<[PowerAssertionKind: IOPMAssertionID]>([:])
    private let notifyTokens = Mutex<[Int32]>([])
    private let logger = HostLogger(category: "KeepAwake")

    public init() {}

    deinit {
        hold([], name: "")
        for token in notifyTokens.withLock({ $0 }) {
            notify_cancel(token)
        }
    }

    @discardableResult
    public func hold(_ kinds: Set<PowerAssertionKind>, name: String) -> Set<PowerAssertionKind> {
        held.withLock { held in
            for (kind, id) in held where !kinds.contains(kind) {
                IOPMAssertionRelease(id)
                held[kind] = nil
            }
            for (_, id) in held {
                IOPMAssertionSetProperty(id, kIOPMAssertionNameKey as CFString, name as CFString)
            }
            for kind in kinds where held[kind] == nil {
                guard let type = kind.ioKitType else { continue }
                var id = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(
                    type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
                if result == kIOReturnSuccess {
                    held[kind] = id
                } else {
                    logger.error("Couldn't take power assertion \(type): \(result)")
                }
            }
            return Set(held.keys)
        }
    }

    public func powerState() -> PowerState {
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

    /// Through notifyd rather than a run loop source: the helper runs an app's run loop, but the
    /// standalone `native-host` only a dispatch main queue. The time-remaining estimate moves with
    /// the charge, which is what the low-battery rule needs.
    public func observePowerChanges(_ onChange: @escaping @Sendable () -> Void) {
        for name in [kIOPSNotifyPowerSource, kIOPSNotifyTimeRemaining] {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, DispatchQueue.global(qos: .utility)) { _ in
                onChange()
            }
            if status == NOTIFY_STATUS_OK {
                notifyTokens.withLock { $0.append(token) }
            }
        }
    }
}

extension PowerAssertionKind {
    /// IOKit's name for it; nil for kinds a newer client sent that this host doesn't know.
    var ioKitType: String? {
        switch self {
        case .preventIdleSleep: kIOPMAssertionTypePreventUserIdleSystemSleep
        case .preventSystemSleep: kIOPMAssertionTypePreventSystemSleep
        case .preventDisplaySleep: kIOPMAssertionTypePreventUserIdleDisplaySleep
        case .unknown: nil
        }
    }
}
