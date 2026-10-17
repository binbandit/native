extension CodeTheme {
    public static let atomOne = CodeTheme(
        id: "atom-one",
        name: "Atom One",
        // one-light.json
        light: CodePalette(
            foreground: CodeColor(rgb: 0x383A42),
            background: CodeColor(rgb: 0xFAFAFA),
            comment: CodeColor(rgb: 0xA0A1A7),
            keyword: CodeColor(rgb: 0xA626A4),
            string: CodeColor(rgb: 0x50A14F),
            constant: CodeColor(rgb: 0x986801),
            function: CodeColor(rgb: 0x4078F2),
            variable: CodeColor(rgb: 0xE45649),
            tag: CodeColor(rgb: 0xE45649),
            type: CodeColor(rgb: 0xC18401),
            operator: CodeColor(rgb: 0x383A42),
            regex: CodeColor(rgb: 0x0184BC),
            invalid: CodeColor(rgb: 0x383A42), // Fallback: foreground.
            punctuation: CodeColor(rgb: 0x383A42), // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x50A14F),
            insertedBackground: CodeColor(rgb: 0x00809B, alpha: 0x33),
            deletedForeground: CodeColor(rgb: 0xE45649),
            deletedBackground: CodeColor(rgb: 0xE45649, alpha: 0x26), // Derived: deleted foreground.
            changedForeground: CodeColor(rgb: 0xA626A4),
            changedBackground: CodeColor(rgb: 0xA626A4, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0xE5E5E6),
            lineHighlight: CodeColor(rgb: 0x383A42, alpha: 0x0C) // Derived: missing line highlight background.
        ),
        // one-dark-pro.json
        dark: CodePalette(
            foreground: CodeColor(rgb: 0xABB2BF),
            background: CodeColor(rgb: 0x282C34),
            comment: CodeColor(rgb: 0x7F848E),
            keyword: CodeColor(rgb: 0xC678DD),
            string: CodeColor(rgb: 0x98C379),
            constant: CodeColor(rgb: 0xD19A66),
            function: CodeColor(rgb: 0x61AFEF),
            variable: CodeColor(rgb: 0xE06C75),
            tag: CodeColor(rgb: 0xE06C75),
            type: CodeColor(rgb: 0xE5C07B),
            operator: CodeColor(rgb: 0xABB2BF),
            regex: CodeColor(rgb: 0x56B6C2),
            invalid: CodeColor(rgb: 0xC24038), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0xABB2BF), // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x98C379),
            insertedBackground: CodeColor(rgb: 0x00809B, alpha: 0x33),
            deletedForeground: CodeColor(rgb: 0xE06C75),
            deletedBackground: CodeColor(rgb: 0xE06C75, alpha: 0x26), // Derived: deleted foreground.
            changedForeground: CodeColor(rgb: 0xABB2BF), // Fallback: gitDecoration.modifiedResourceForeground.
            changedBackground: CodeColor(rgb: 0xABB2BF, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x677696, alpha: 0x60),
            lineHighlight: CodeColor(rgb: 0x2C313C)
        )
    )
}
