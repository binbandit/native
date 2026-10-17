extension CodeTheme {
    public static let nord = CodeTheme(
        id: "nord",
        name: "Nord",
        dark: CodePalette(
            // nord.json
            foreground: CodeColor(rgb: 0xD8DEE9),
            background: CodeColor(rgb: 0x2E3440),
            comment: CodeColor(rgb: 0x616E88),
            keyword: CodeColor(rgb: 0x81A1C1),
            string: CodeColor(rgb: 0xA3BE8C),
            constant: CodeColor(rgb: 0xB48EAD),
            function: CodeColor(rgb: 0x88C0D0),
            variable: CodeColor(rgb: 0xD8DEE9), // Fallback: foreground.
            tag: CodeColor(rgb: 0x81A1C1),
            type: CodeColor(rgb: 0x8FBCBB), // Fallback: entity.name.class.
            operator: CodeColor(rgb: 0x81A1C1),
            regex: CodeColor(rgb: 0xEBCB8B),
            invalid: CodeColor(rgb: 0xBF616A), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0xECEFF4),
            insertedForeground: CodeColor(rgb: 0xA3BE8C),
            insertedBackground: CodeColor(rgb: 0x81A1C1, alpha: 0x33),
            deletedForeground: CodeColor(rgb: 0xBF616A),
            deletedBackground: CodeColor(rgb: 0xBF616A, alpha: 0x4D),
            changedForeground: CodeColor(rgb: 0xEBCB8B),
            changedBackground: CodeColor(rgb: 0xEBCB8B, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x434C5E, alpha: 0xCC),
            lineHighlight: CodeColor(rgb: 0x3B4252)
        )
    )
}
