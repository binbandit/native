extension CodePalette {
    /// The palette drawn on `background` instead of its own: each text role is darkened (on a light
    /// background) or lightened (on a dark one) just enough to keep the contrast it had on the
    /// palette's own background, so a theme can sit on the app's surface (Native's on Wool, say)
    /// without losing legibility. Fills and the diff tints are left as they are.
    public func preservingContrast(on background: CodeColor) -> CodePalette {
        func adjusted(_ color: CodeColor) -> CodeColor {
            color.keepingContrast(color.contrastRatio(with: self.background), on: background)
        }
        return CodePalette(
            foreground: adjusted(foreground),
            background: background,
            comment: adjusted(comment),
            keyword: adjusted(keyword),
            string: adjusted(string),
            constant: adjusted(constant),
            function: adjusted(function),
            variable: adjusted(variable),
            tag: adjusted(tag),
            type: adjusted(type),
            operator: adjusted(`operator`),
            regex: adjusted(regex),
            invalid: adjusted(invalid),
            punctuation: adjusted(punctuation),
            insertedForeground: adjusted(insertedForeground),
            insertedBackground: insertedBackground,
            deletedForeground: adjusted(deletedForeground),
            deletedBackground: deletedBackground,
            changedForeground: adjusted(changedForeground),
            changedBackground: changedBackground,
            selection: selection,
            lineHighlight: lineHighlight,
            strong: strong
        )
    }
}

extension CodeColor {
    /// This color, moved toward black or white in small steps until it has at least `ratio` against
    /// `background` (or can't move further).
    func keepingContrast(_ ratio: Double, on background: CodeColor) -> CodeColor {
        let darkens = background.relativeLuminance > 0.5
        var color = self
        var step = 0
        while color.contrastRatio(with: background) < ratio, step < 100 {
            step += 1
            let factor = darkens ? 1 - Double(step) / 100 : Double(step) / 100
            func channel(_ value: UInt8) -> UInt8 {
                let value = Double(value)
                return UInt8((darkens ? value * factor : value + (255 - value) * factor).rounded())
            }
            color = CodeColor(red: channel(red), green: channel(green), blue: channel(blue), alpha: alpha)
        }
        return color
    }
}
