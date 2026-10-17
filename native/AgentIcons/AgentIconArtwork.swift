import CoreGraphics

/// What an agent's icon turned out to be.
enum AgentIconArtwork {
    /// A full-color image shown as is: an installed app's icon, or a plugin's own bitmap.
    case picture(CGImage)
    /// A monochrome vector drawn in the text color: the registry's icon, or a plugin's SVG.
    case glyph(AgentIconGlyph)
    /// The first letter of the agent's name, when nothing else was found.
    case monogram(String)

    /// The monogram for a name: its first letter or digit, uppercased; a dot when it has neither.
    static func monogram(for name: String) -> Self {
        .monogram(name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "·")
    }

    /// Glyphs and monograms take the color of the text around them; pictures keep their own.
    var isTemplate: Bool {
        switch self {
        case .picture: false
        case .glyph, .monogram: true
        }
    }
}
