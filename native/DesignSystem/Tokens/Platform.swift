import SwiftUI

#if canImport(AppKit)
import AppKit

/// The platform's font type (`NSFont` on macOS, `UIFont` on iPadOS), for text views that need the
/// design system's type outside SwiftUI.
public typealias DSPlatformFont = NSFont
typealias DSPlatformColor = NSColor
#else
import UIKit

public typealias DSPlatformFont = UIFont
typealias DSPlatformColor = UIColor
#endif

extension DS {
    /// Whether the platform is touch-first (iPadOS). Components keep the same visuals, but grow
    /// their hit areas and never hide an action behind hover.
    public static let isTouchPlatform: Bool = {
        #if os(iOS)
        true
        #else
        false
        #endif
    }()
}

extension DS.Size {
    /// The smallest comfortable touch target (Apple's 44pt); nothing on the Mac.
    public static let minimumHitTarget: CGFloat = DS.isTouchPlatform ? 44 : 0
    /// The height of a sidebar task row: Conductor's 36pt on the Mac, a full touch target on iPadOS.
    public static let rowMinHeight: CGFloat = DS.isTouchPlatform ? 44 : 36
}

extension View {
    /// Grows the hit area of a control drawn at `size` to the platform's minimum touch target,
    /// without changing its look or layout. A no-op on the Mac.
    public func dsHitTarget(_ size: CGFloat) -> some View {
        let outset = max(0, (DS.Size.minimumHitTarget - size) / 2)
        return contentShape(.interaction, Rectangle().inset(by: -outset))
    }
}

extension View {
    /// The shape the keyboard focus ring follows (macOS; iPadOS draws its own).
    public func dsFocusShape(_ shape: some Shape) -> some View {
        #if os(macOS)
        contentShape(.focusEffect, shape)
        #else
        self
        #endif
    }
}

/// Copies text to the general pasteboard.
enum DSPasteboard {
    static func copy(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

extension DSPlatformColor {
    /// An sRGB color from a 0xRRGGBB literal.
    nonisolated static func dsSRGB(_ hex: UInt32, alpha: CGFloat = 1) -> DSPlatformColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        #if canImport(AppKit)
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// A color that picks its light or dark value from the appearance it resolves in.
    nonisolated static func dsDynamic(name: String, light: DSPlatformColor, dark: DSPlatformColor) -> DSPlatformColor {
        #if canImport(AppKit)
        NSColor(name: "ds.\(name)") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        #else
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
        #endif
    }
}
