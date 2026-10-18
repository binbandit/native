import Foundation

#if os(macOS)
import IOKit.ps
#endif

/// Whether background work should wait to save energy, and when that might have changed. On iPad
/// and iPhone only Low Power Mode counts: heavy background work runs on a host, not there.
nonisolated enum PlatformPowerSource {
    /// On battery, or in Low Power Mode.
    static var prefersSavingEnergy: Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }
        #if os(macOS)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
        #else
        return false
        #endif
    }

    /// Returns at the next power change (plugged in or out, Low Power Mode on or off), or after
    /// ten minutes, whichever comes first, so a missed notification can't stall work for good.
    static func change() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                    return
                }
            }
            #if os(macOS)
            group.addTask {
                for await _ in PowerSourceChanges.stream() {
                    return
                }
            }
            #endif
            group.addTask {
                try? await Task.sleep(for: .seconds(600))
            }
            await group.next()
            group.cancelAll()
        }
    }
}

#if os(macOS)
/// IOKit's power-source notification as a stream, delivered on the main run loop.
nonisolated private enum PowerSourceChanges {
    static func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let registration = Registration(continuation)
            continuation.onTermination = { _ in registration.cancel() }
        }
    }

    /// Owns the run loop source; the stream's termination handler keeps it alive until then.
    private final class Registration: @unchecked Sendable {
        private let continuation: AsyncStream<Void>.Continuation
        private var source: CFRunLoopSource?

        init(_ continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
            let callback: IOPowerSourceCallbackType = { context in
                guard let context else { return }
                Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue().continuation.yield()
            }
            source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?
                .takeRetainedValue()
            if let source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            } else {
                continuation.finish()
            }
        }

        func cancel() {
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            }
            source = nil
        }
    }
}
#endif
