import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension PlatformApplication {
    /// Whether any of Native's windows can be seen at all: not hidden, minimized, fully covered or
    /// in the background. Work that only feeds what's on screen waits while it's false.
    static var isVisible: Bool {
        #if canImport(AppKit)
        NSApplication.shared.occlusionState.contains(.visible)
        #else
        UIApplication.shared.applicationState != .background
        #endif
    }

    /// Posted when `isVisible` may have changed.
    static var visibilityNotifications: [Notification.Name] {
        #if canImport(AppKit)
        [NSApplication.didChangeOcclusionStateNotification]
        #else
        [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification]
        #endif
    }
}
