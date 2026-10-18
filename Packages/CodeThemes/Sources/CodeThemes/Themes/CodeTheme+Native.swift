extension CodeTheme {
    public static let native = CodeTheme(
        id: "native",
        name: "Native",
        // Native DesignSystem light semantic tokens, darkened where AA contrast requires it.
        light: CodePalette(
            foreground: CodeColor(rgb: 0x181818),
            background: CodeColor(rgb: 0xFFFFFF),
            comment: CodeColor(rgb: 0x6E6E6E),
            keyword: CodeColor(rgb: 0x8250DF),
            string: CodeColor(rgb: 0x0B7A34),
            constant: CodeColor(rgb: 0xA35200),
            function: CodeColor(rgb: 0x2463EB),
            variable: CodeColor(rgb: 0x181818),
            tag: CodeColor(rgb: 0xDC2828),
            type: CodeColor(rgb: 0x9A6700),
            operator: CodeColor(rgb: 0x8250DF),
            regex: CodeColor(rgb: 0xA35200),
            invalid: CodeColor(rgb: 0xDC2828),
            punctuation: CodeColor(rgb: 0x505050),
            insertedForeground: CodeColor(rgb: 0x0B7A34),
            insertedBackground: CodeColor(rgb: 0x0B7A34, alpha: 0x26),
            deletedForeground: CodeColor(rgb: 0xDC2828),
            deletedBackground: CodeColor(rgb: 0xDC2828, alpha: 0x26),
            changedForeground: CodeColor(rgb: 0x9A6700),
            changedBackground: CodeColor(rgb: 0x9A6700, alpha: 0x26),
            selection: CodeColor(rgb: 0x000000, alpha: 0x14),
            lineHighlight: CodeColor(rgb: 0x000000, alpha: 0x0B)
        ),
        // Native's dark mode: a restrained, mostly monochrome set on the design system's code wells
        // (#070708). Keywords are the primary text in semibold, names a quieter gray, types a muted
        // cyan, strings and numbers muted warm tones, and punctuation and comments step down from
        // there. Every text role clears 4.5:1 on the wells and on the raised surface diffs use.
        dark: CodePalette(
            foreground: CodeColor(rgb: 0xC4C4C4),
            background: CodeColor(rgb: 0x070708),
            comment: CodeColor(rgb: 0x85858A),
            keyword: CodeColor(rgb: 0xE9E9E6),
            string: CodeColor(rgb: 0xCDB48E),
            constant: CodeColor(rgb: 0xD9A47E),
            function: CodeColor(rgb: 0xC4C4C4),
            variable: CodeColor(rgb: 0xC4C4C4),
            tag: CodeColor(rgb: 0x94C6D4),
            type: CodeColor(rgb: 0x94C6D4),
            operator: CodeColor(rgb: 0xA5A5A8),
            regex: CodeColor(rgb: 0xCDB48E),
            invalid: CodeColor(rgb: 0xF87272),
            punctuation: CodeColor(rgb: 0x8D8D91),
            insertedForeground: CodeColor(rgb: 0x4ADE80),
            insertedBackground: CodeColor(rgb: 0x4ADE80, alpha: 0x26),
            deletedForeground: CodeColor(rgb: 0xF87272),
            deletedBackground: CodeColor(rgb: 0xF87272, alpha: 0x26),
            changedForeground: CodeColor(rgb: 0xD29922),
            changedBackground: CodeColor(rgb: 0xD29922, alpha: 0x26),
            selection: CodeColor(rgb: 0xFFFFFF, alpha: 0x1A),
            lineHighlight: CodeColor(rgb: 0xFFFFFF, alpha: 0x0F),
            strong: [.keyword]
        )
    )
}
