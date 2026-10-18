import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension PlatformApplication {
    /// Posted when the user comes back to Native.
    static var didBecomeActiveNotification: Notification.Name {
        #if canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }
}
