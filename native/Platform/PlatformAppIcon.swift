import AppAppearance
import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The app icon on each platform, behind one adapter so preferences and celebrations stay shared.
///
/// - Mac: any image applies at runtime through the Dock (`applicationIconImage`). A runtime image is
///   flat, so it loses the compiled icon's Clear and Tinted appearances; nil restores the compiled
///   icon stack with all of them.
/// - iPad and iPhone: iOS only switches between alternate icons compiled into the bundle
///   (`setAlternateIconName`), so a plugin's images can't become the home-screen icon there; they
///   still restyle Home in the app. Built-in themes will apply once those targets ship them as
///   alternate icons, through `alternateIconName(for:)`.
@MainActor
final class PlatformAppIcon {
    /// Called with whether the system appearance is dark, at start and whenever it changes.
    var onAppearanceChange: ((Bool) -> Void)?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    #if canImport(AppKit)
    private var appearanceObservation: NSKeyValueObservation?
    #endif

    func start() {
        guard observers.isEmpty else { return }
        #if canImport(AppKit)
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in self?.notify() }
        }
        let activation = NSApplication.didBecomeActiveNotification
        #elseif canImport(UIKit)
        let activation = UIApplication.didBecomeActiveNotification
        #endif
        observers = [
            (
                NotificationCenter.default,
                NotificationCenter.default.addObserver(forName: activation, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.notify() }
                }
            )
        ]
        notify()
    }

    /// Whether `image` can be the app icon on this platform.
    static func canApply(_ image: AppIconImage) -> Bool {
        #if canImport(AppKit)
        true
        #else
        alternateIconName(for: image) != nil
        #endif
    }

    /// Shows `image` as the app icon; nil restores the compiled icon.
    func apply(_ image: AppIconImage?) {
        #if canImport(AppKit)
        NSApplication.shared.applicationIconImage = image.flatMap(Self.platformImage)
        #elseif canImport(UIKit)
        let name = image.flatMap(Self.alternateIconName)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name, completionHandler: nil)
        #endif
    }

    /// Whether the asset catalog has an image by this name, for checking built-in artwork.
    static func hasAsset(named name: String) -> Bool {
        #if canImport(AppKit)
        NSImage(named: name) != nil
        #elseif canImport(UIKit)
        UIImage(named: name) != nil
        #else
        false
        #endif
    }

    /// A preview of `image`, wherever it comes from.
    static func preview(_ image: AppIconImage) -> Image {
        switch image {
        case .asset(let name): return Image(name)
        case .file:
            #if canImport(AppKit)
            if let loaded = platformImage(image) { return Image(nsImage: loaded) }
            #elseif canImport(UIKit)
            if case .file(let url) = image, let loaded = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                return Image(uiImage: loaded)
            }
            #endif
            return Image(systemName: "app.dashed")
        }
    }

    static var bundledPreview: Image {
        #if canImport(AppKit)
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        #else
        Image("AppIcon-original-light")
        #endif
    }

    #if canImport(AppKit)
    private static func platformImage(_ image: AppIconImage) -> NSImage? {
        switch image {
        case .asset(let name): NSImage(named: name)
        case .file(let url): NSImage(contentsOf: url)
        }
    }
    #elseif canImport(UIKit)
    /// The compiled alternate icon that stands for `image`. None ship yet; plugin files never can.
    private static func alternateIconName(for image: AppIconImage) -> String? {
        nil
    }
    #endif

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
        onAppearanceChange?(isDark)
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}
