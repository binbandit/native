import Foundation
import IOKit.ps

/// Calls back on the main run loop whenever the Mac switches between battery and power or its
/// charge changes, for the battery rules.
final class PowerSourceMonitor {
    private let onChange: () -> Void
    private var source: CFRunLoopSource?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // The source is on the main run loop, so this is the main thread.
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        }, context)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    isolated deinit {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}
