import Foundation
import NativeTelemetry

#if os(macOS)
import IOKit.ps
#endif

/// Sends only when it costs the user nothing: not in Low Power Mode, not while the Mac is hot, and
/// on a Mac only while it's on power. Held events wait in the pipeline's bounded backlog.
struct TelemetrySendingWindow: TelemetrySendingConditions {
    func allowsSending() async -> Bool {
        let process = ProcessInfo.processInfo
        guard !process.isLowPowerModeEnabled else { return false }
        switch process.thermalState {
        case .serious, .critical: return false
        default: break
        }
        #if os(macOS)
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return source == kIOPMACPowerKey
        #else
        return true
        #endif
    }
}
