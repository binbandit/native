extension CodePalette {
    /// The 16 ANSI colors for a terminal drawn in this theme (black, red, green, yellow, blue,
    /// magenta, cyan, white, then the bright variants), taken from the theme's own roles so `ls`,
    /// `git` and test runners match its code blocks: red from deletions, green from insertions,
    /// yellow from changes, blue from functions, magenta from keywords, cyan from types, black and
    /// white from the background and text. Bright variants move a step toward the text color.
    public func ansiColors(for appearance: CodeAppearance) -> [CodeColor] {
        let isDark = appearance == .dark
        let opaque = { (color: CodeColor) in color.composited(over: background) }
        let black = isDark ? background.mixed(with: foreground, amount: 0.18) : foreground
        let white = isDark ? foreground : background.mixed(with: foreground, amount: 0.22)
        let hues = [deletedForeground, insertedForeground, changedForeground, function, keyword, type].map(opaque)
        let normal = [black] + hues + [white]
        let bright =
            [opaque(comment)]
            + hues.map { $0.mixed(with: isDark ? CodeColor(rgb: 0xFFFFFF) : CodeColor(rgb: 0), amount: 0.2) }
            + [
                isDark
                    ? foreground.mixed(with: CodeColor(rgb: 0xFFFFFF), amount: 0.5)
                    : background.mixed(with: foreground, amount: 0.12)
            ]
        return normal + bright
    }
}

extension CodeColor {
    /// This color moved `amount` (0...1) of the way to `other`, opaque.
    func mixed(with other: CodeColor, amount: Double) -> CodeColor {
        func channel(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * amount).rounded())
        }
        return CodeColor(
            red: channel(red, other.red), green: channel(green, other.green), blue: channel(blue, other.blue))
    }
}
