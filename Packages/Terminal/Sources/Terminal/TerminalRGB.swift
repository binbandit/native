/// An opaque sRGB color, the form terminal renderers take colors in.
public struct TerminalRGB: Hashable, Sendable, CustomStringConvertible {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A color from a 0xRRGGBB literal.
    public init(_ hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    /// A color from components in 0...1, as AppKit and SwiftUI resolve them; out-of-range values
    /// (extended sRGB) are clamped.
    public init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        self.init(red: channel(red), green: channel(green), blue: channel(blue))
    }

    /// `#rrggbb`, as Ghostty's config reads colors.
    public var description: String {
        "#" + [red, green, blue].map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }

    /// This color laid over `background` at `opacity` (0...1), the way a translucent fill composites.
    public func over(_ background: TerminalRGB, opacity: Double) -> TerminalRGB {
        let alpha = min(max(opacity, 0), 1)
        func mix(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Double(top) * alpha + Double(bottom) * (1 - alpha)).rounded())
        }
        return TerminalRGB(red: mix(red, background.red), green: mix(green, background.green), blue: mix(blue, background.blue))
    }
}
