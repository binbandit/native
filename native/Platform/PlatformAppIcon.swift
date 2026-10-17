import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Dock overrides are macOS-only; the shared preferences can still be loaded by iPad clients.
@MainActor
final class PlatformAppIcon {
    var onEnvironmentChange: ((Bool) -> Void)?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    #if canImport(AppKit)
    private var appearanceObservation: NSKeyValueObservation?
    #endif

    func start() {
        guard observers.isEmpty else { return }
        var notifications: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSCalendarDayChanged),
            (.default, .NSSystemTimeZoneDidChange),
        ]
        #if canImport(AppKit)
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in self?.notify() }
        }
        notifications += [
            (.default, NSApplication.didBecomeActiveNotification),
            (.default, .NSSystemClockDidChange),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        #elseif canImport(UIKit)
        notifications.append((.default, UIApplication.didBecomeActiveNotification))
        #endif
        observers = notifications.map { center, name in
            (
                center,
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.notify() }
                }
            )
        }
        notify()
    }

    func apply(imageNamed name: String?) {
        #if canImport(AppKit)
        // Nil restores the channel's compiled icon stack, retaining all native system appearances.
        NSApplication.shared.applicationIconImage = name.flatMap { NSImage(named: $0) }
        #endif
    }

    static var bundledPreview: Image {
        #if canImport(AppKit)
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        #else
        Image("AppIcon-original-light")
        #endif
    }

    private func notify() {
        #if canImport(AppKit)
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        #elseif canImport(UIKit)
        let isDark =
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first?.traitCollection.userInterfaceStyle == .dark
        #else
        let isDark = false
        #endif
        onEnvironmentChange?(isDark)
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}
