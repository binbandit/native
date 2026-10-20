import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// How this device introduces itself to a host it pairs with ("Brayden's MacBook Pro", "Mac",
/// "macOS 27.1"), so the host's list of paired devices names it the way its owner would.
enum PlatformDevice {
    static var name: String {
        #if os(macOS)
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        UIDevice.current.name
        #endif
    }

    static var model: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.model
        #endif
    }

    static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let system = "macOS"
        #else
        let system = UIDevice.current.systemName
        #endif
        return "\(system) \(version.majorVersion).\(version.minorVersion)"
    }
}
