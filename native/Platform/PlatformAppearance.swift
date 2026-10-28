import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The app's light or dark appearance on each platform. A SwiftUI `preferredColorScheme` only
/// reaches SwiftUI views and doesn't reliably let go again, so this sets it where the platform
/// keeps it for the whole app:
///
/// - Mac: `NSApp.appearance`, which every window, sheet, popover, menu and AppKit view inherits
///   (nil follows the system again).
/// - iPad: each window scene's `traitOverrides`, which reach every window in the scene, including
///   ones it opens later. Scenes that connect later get it as they connect.
@MainActor
final class PlatformAppearance {
    #if canImport(UIKit) && !canImport(AppKit)
    private var scheme: ColorScheme?
    private var observer: (any NSObjectProtocol)?
    #endif

    /// Makes the app `scheme`, or follows the system for nil.
    func apply(_ scheme: ColorScheme?) {
        #if canImport(AppKit)
        NSApplication.shared.appearance = scheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
        #elseif canImport(UIKit)
        self.scheme = scheme
        observeNewScenes()
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            apply(to: scene)
        }
        #endif
    }

    /// Light or dark as the app shows now: what `apply(_:)` set, or the system's.
    var current: ColorScheme {
        #if canImport(AppKit)
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        #else
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
        return scene?.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        #endif
    }

    #if canImport(UIKit) && !canImport(AppKit)
    private func apply(to scene: UIWindowScene) {
        switch scheme {
        case .dark: scene.traitOverrides.userInterfaceStyle = .dark
        case .light: scene.traitOverrides.userInterfaceStyle = .light
        default: scene.traitOverrides.remove(UITraitUserInterfaceStyle.self)
        }
    }

    private func observeNewScenes() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let scene = notification.object as? UIWindowScene else { return }
                self?.apply(to: scene)
            }
        }
    }

    isolated deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }
    #endif
}
