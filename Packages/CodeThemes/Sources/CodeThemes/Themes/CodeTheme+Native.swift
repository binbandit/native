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
            variable: CodeColor(rgb: 0x1D65B7),
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
        // Native DesignSystem dark semantic tokens.
        dark: CodePalette(
            foreground: CodeColor(rgb: 0xEDEDED),
            background: CodeColor(rgb: 0x171717),
            comment: CodeColor(rgb: 0x8A8A8A),
            keyword: CodeColor(rgb: 0xA371F7),
            string: CodeColor(rgb: 0x4ADE80),
            constant: CodeColor(rgb: 0xF59E3B),
            function: CodeColor(rgb: 0x61A6FA),
            variable: CodeColor(rgb: 0xEDEDED),
            tag: CodeColor(rgb: 0xF87272),
            type: CodeColor(rgb: 0xD29922),
            operator: CodeColor(rgb: 0xA371F7),
            regex: CodeColor(rgb: 0xF59E3B),
            invalid: CodeColor(rgb: 0xF87272),
            punctuation: CodeColor(rgb: 0xAFAFAF),
            insertedForeground: CodeColor(rgb: 0x4ADE80),
            insertedBackground: CodeColor(rgb: 0x4ADE80, alpha: 0x26),
            deletedForeground: CodeColor(rgb: 0xF87272),
            deletedBackground: CodeColor(rgb: 0xF87272, alpha: 0x26),
            changedForeground: CodeColor(rgb: 0xD29922),
            changedBackground: CodeColor(rgb: 0xD29922, alpha: 0x26),
            selection: CodeColor(rgb: 0xFFFFFF, alpha: 0x1A),
            lineHighlight: CodeColor(rgb: 0xFFFFFF, alpha: 0x0F)
        )
    )
}
