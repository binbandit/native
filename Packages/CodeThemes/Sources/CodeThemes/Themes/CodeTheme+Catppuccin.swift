extension CodeTheme {
    public static let catppuccinLatte = CodeTheme(
        id: "catppuccin-latte",
        name: "Catppuccin Latte",
        light: CodePalette(
            // catppuccin-latte.json
            foreground: CodeColor(rgb: 0x4C4F69),
            background: CodeColor(rgb: 0xEFF1F5),
            comment: CodeColor(rgb: 0x7C7F93),
            keyword: CodeColor(rgb: 0x8839EF),
            string: CodeColor(rgb: 0x40A02B),
            constant: CodeColor(rgb: 0xFE640B),
            function: CodeColor(rgb: 0x1E66F5),
            variable: CodeColor(rgb: 0x4C4F69), // Fallback: foreground.
            tag: CodeColor(rgb: 0x1E66F5),
            type: CodeColor(rgb: 0xDF8E1D),
            operator: CodeColor(rgb: 0x179299),
            regex: CodeColor(rgb: 0x40A02B),
            invalid: CodeColor(rgb: 0xD20F39), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0x7C7F93),
            insertedForeground: CodeColor(rgb: 0x40A02B), // Fallback: gitDecoration.addedResourceForeground.
            insertedBackground: CodeColor(rgb: 0x40A02B, alpha: 0x33),
            deletedForeground: CodeColor(rgb: 0xD20F39), // Fallback: gitDecoration.deletedResourceForeground.
            deletedBackground: CodeColor(rgb: 0xD20F39, alpha: 0x33),
            changedForeground: CodeColor(rgb: 0xDF8E1D), // Fallback: gitDecoration.modifiedResourceForeground.
            changedBackground: CodeColor(rgb: 0xDF8E1D, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x7C7F93, alpha: 0x4D),
            lineHighlight: CodeColor(rgb: 0x4C4F69, alpha: 0x12)
        )
    )

    public static let catppuccinMacchiato = CodeTheme(
        id: "catppuccin-macchiato",
        name: "Catppuccin Macchiato",
        dark: CodePalette(
            // catppuccin-macchiato.json
            foreground: CodeColor(rgb: 0xCAD3F5),
            background: CodeColor(rgb: 0x24273A),
            comment: CodeColor(rgb: 0x939AB7),
            keyword: CodeColor(rgb: 0xC6A0F6),
            string: CodeColor(rgb: 0xA6DA95),
            constant: CodeColor(rgb: 0xF5A97F),
            function: CodeColor(rgb: 0x8AADF4),
            variable: CodeColor(rgb: 0xCAD3F5), // Fallback: foreground.
            tag: CodeColor(rgb: 0x8AADF4),
            type: CodeColor(rgb: 0xEED49F),
            operator: CodeColor(rgb: 0x8BD5CA),
            regex: CodeColor(rgb: 0xA6DA95),
            invalid: CodeColor(rgb: 0xED8796), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0x939AB7),
            insertedForeground: CodeColor(rgb: 0xA6DA95), // Fallback: gitDecoration.addedResourceForeground.
            insertedBackground: CodeColor(rgb: 0xA6DA95, alpha: 0x33),
            deletedForeground: CodeColor(rgb: 0xED8796), // Fallback: gitDecoration.deletedResourceForeground.
            deletedBackground: CodeColor(rgb: 0xED8796, alpha: 0x33),
            changedForeground: CodeColor(rgb: 0xEED49F), // Fallback: gitDecoration.modifiedResourceForeground.
            changedBackground: CodeColor(rgb: 0xEED49F, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x939AB7, alpha: 0x40),
            lineHighlight: CodeColor(rgb: 0xCAD3F5, alpha: 0x12)
        )
    )

    public static let catppuccinMocha = CodeTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        dark: CodePalette(
            // catppuccin-mocha.json
            foreground: CodeColor(rgb: 0xCDD6F4),
            background: CodeColor(rgb: 0x1E1E2E),
            comment: CodeColor(rgb: 0x9399B2),
            keyword: CodeColor(rgb: 0xCBA6F7),
            string: CodeColor(rgb: 0xA6E3A1),
            constant: CodeColor(rgb: 0xFAB387),
            function: CodeColor(rgb: 0x89B4FA),
            variable: CodeColor(rgb: 0xCDD6F4), // Fallback: foreground.
            tag: CodeColor(rgb: 0x89B4FA),
            type: CodeColor(rgb: 0xF9E2AF),
            operator: CodeColor(rgb: 0x94E2D5),
            regex: CodeColor(rgb: 0xA6E3A1),
            invalid: CodeColor(rgb: 0xF38BA8), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0x9399B2),
            insertedForeground: CodeColor(rgb: 0xA6E3A1), // Fallback: gitDecoration.addedResourceForeground.
            insertedBackground: CodeColor(rgb: 0xA6E3A1, alpha: 0x33),
            deletedForeground: CodeColor(rgb: 0xF38BA8), // Fallback: gitDecoration.deletedResourceForeground.
            deletedBackground: CodeColor(rgb: 0xF38BA8, alpha: 0x33),
            changedForeground: CodeColor(rgb: 0xF9E2AF), // Fallback: gitDecoration.modifiedResourceForeground.
            changedBackground: CodeColor(rgb: 0xF9E2AF, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x9399B2, alpha: 0x40),
            lineHighlight: CodeColor(rgb: 0xCDD6F4, alpha: 0x12)
        )
    )
}
