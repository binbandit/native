import AppKit
import SwiftUI

// Stand-ins for the design system's categorical chart tokens, until `TokensColor.swift` has them.
// Delete this file in the change that adds them there: the names and values are the same. The three
// were checked with the dataviz palette validator (all pairs, protanopia and deuteranopia) on both
// appearances' surfaces.
nonisolated extension ShapeStyle where Self == Color {
    static var dsChart1: Color { ChartPalette.blue }
    static var dsChart2: Color { ChartPalette.orange }
    static var dsChart3: Color { ChartPalette.aqua }
}

nonisolated private enum ChartPalette {
    static let blue = dynamic("chart1", light: 0x2A78D6, dark: 0x3987E5)
    static let orange = dynamic("chart2", light: 0xEB6834, dark: 0xD95926)
    static let aqua = dynamic("chart3", light: 0x1BAF7A, dark: 0x199E70)

    static func dynamic(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: "ds.\(name)") { appearance in
            srgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
