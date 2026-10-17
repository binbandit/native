extension CodeTheme {
    public static let solarized = CodeTheme(
        id: "solarized",
        name: "Solarized",
        // solarized-light.json
        light: CodePalette(
            foreground: CodeColor(rgb: 0x586E75),  // Derived: darker upstream base01 preserves AA contrast.
            background: CodeColor(rgb: 0xFDF6E3),
            comment: CodeColor(rgb: 0x93A1A1),
            keyword: CodeColor(rgb: 0x859900),
            string: CodeColor(rgb: 0x2AA198),
            constant: CodeColor(rgb: 0xD33682),
            function: CodeColor(rgb: 0x268BD2),
            variable: CodeColor(rgb: 0x657B83),  // Fallback: foreground.
            tag: CodeColor(rgb: 0x268BD2),
            type: CodeColor(rgb: 0xCB4B16),
            operator: CodeColor(rgb: 0x859900),
            regex: CodeColor(rgb: 0xDC322F),
            invalid: CodeColor(rgb: 0xDC322F),
            punctuation: CodeColor(rgb: 0x657B83),  // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x859900),
            insertedBackground: CodeColor(rgb: 0x859900, alpha: 0x26),  // Derived: inserted foreground.
            deletedForeground: CodeColor(rgb: 0xDC322F),
            deletedBackground: CodeColor(rgb: 0xDC322F, alpha: 0x26),  // Derived: deleted foreground.
            changedForeground: CodeColor(rgb: 0xCB4B16),
            changedBackground: CodeColor(rgb: 0xCB4B16, alpha: 0x26),  // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0xEEE8D5),
            lineHighlight: CodeColor(rgb: 0xEEE8D5)
        ),
        // solarized-dark.json
        dark: CodePalette(
            foreground: CodeColor(rgb: 0x839496),
            background: CodeColor(rgb: 0x002B36),
            comment: CodeColor(rgb: 0x586E75),
            keyword: CodeColor(rgb: 0x859900),
            string: CodeColor(rgb: 0x2AA198),
            constant: CodeColor(rgb: 0xD33682),
            function: CodeColor(rgb: 0x268BD2),
            variable: CodeColor(rgb: 0x839496),  // Fallback: foreground.
            tag: CodeColor(rgb: 0x268BD2),
            type: CodeColor(rgb: 0xCB4B16),
            operator: CodeColor(rgb: 0x859900),
            regex: CodeColor(rgb: 0xDC322F),
            invalid: CodeColor(rgb: 0xDC322F),
            punctuation: CodeColor(rgb: 0x839496),  // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x859900),
            insertedBackground: CodeColor(rgb: 0x859900, alpha: 0x26),  // Derived: inserted foreground.
            deletedForeground: CodeColor(rgb: 0xDC322F),
            deletedBackground: CodeColor(rgb: 0xDC322F, alpha: 0x26),  // Derived: deleted foreground.
            changedForeground: CodeColor(rgb: 0xCB4B16),
            changedBackground: CodeColor(rgb: 0xCB4B16, alpha: 0x26),  // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x274642),
            lineHighlight: CodeColor(rgb: 0x073642)
        )
    )
}
