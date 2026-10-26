import Darwin

/// An 8-bit sRGB color with alpha. Plain values rather than SwiftUI colors keep the package UI-free, so the host and
/// the companion can share themes; the app converts at the edge.
public struct CodeColor: Sendable, Hashable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(rgb: UInt32, alpha: UInt8 = 0xFF) {
        red = UInt8((rgb >> 16) & 0xFF)
        green = UInt8((rgb >> 8) & 0xFF)
        blue = UInt8(rgb & 0xFF)
        self.alpha = alpha
    }

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 0xFF) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var description: String {
        let rgb = "#\(Self.hex(red))\(Self.hex(green))\(Self.hex(blue))"
        return alpha == 0xFF ? rgb : "\(rgb)\(Self.hex(alpha))"
    }

    public func composited(over background: CodeColor) -> CodeColor {
        let foregroundAlpha = Double(alpha) / 255
        let backgroundAlpha = Double(background.alpha) / 255
        let resultAlpha = foregroundAlpha + backgroundAlpha * (1 - foregroundAlpha)

        guard resultAlpha > 0 else {
            return CodeColor(red: 0, green: 0, blue: 0, alpha: 0)
        }

        func channel(_ foreground: UInt8, _ background: UInt8) -> UInt8 {
            let value =
                (Double(foreground) * foregroundAlpha
                    + Double(background) * backgroundAlpha * (1 - foregroundAlpha)) / resultAlpha
            return UInt8(value.rounded())
        }

        return CodeColor(
            red: channel(red, background.red),
            green: channel(green, background.green),
            blue: channel(blue, background.blue),
            alpha: UInt8((resultAlpha * 255).rounded())
        )
    }

    public var relativeLuminance: Double {
        0.2126 * Self.linearized(red) + 0.7152 * Self.linearized(green) + 0.0722 * Self.linearized(blue)
    }

    /// WCAG contrast ratio. Alpha is ignored, so composite a translucent color over its background first.
    public func contrastRatio(with other: CodeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func hex(_ value: UInt8) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return value < 0x10 ? "0\(digits)" : digits
    }

    private static func linearized(_ value: UInt8) -> Double {
        let component = Double(value) / 255
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}
