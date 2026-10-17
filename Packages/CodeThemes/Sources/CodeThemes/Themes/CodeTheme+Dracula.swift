extension CodeTheme {
    public static let dracula = CodeTheme(
        id: "dracula",
        name: "Dracula",
        dark: CodePalette(
            // dracula.json
            foreground: CodeColor(rgb: 0xF8F8F2),
            background: CodeColor(rgb: 0x282A36),
            comment: CodeColor(rgb: 0x6272A4),
            keyword: CodeColor(rgb: 0xFF79C6),
            string: CodeColor(rgb: 0xF1FA8C),
            constant: CodeColor(rgb: 0xBD93F9),
            function: CodeColor(rgb: 0x50FA7B),
            variable: CodeColor(rgb: 0xF8F8F2),
            tag: CodeColor(rgb: 0xFF79C6),
            type: CodeColor(rgb: 0x8BE9FD),
            operator: CodeColor(rgb: 0xFF79C6),
            regex: CodeColor(rgb: 0xF1FA8C),
            invalid: CodeColor(rgb: 0xFF5555),
            punctuation: CodeColor(rgb: 0xF8F8F2), // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x50FA7B),
            insertedBackground: CodeColor(rgb: 0x50FA7B, alpha: 0x20),
            deletedForeground: CodeColor(rgb: 0xFF5555),
            deletedBackground: CodeColor(rgb: 0xFF5555, alpha: 0x50),
            changedForeground: CodeColor(rgb: 0xFFB86C),
            changedBackground: CodeColor(rgb: 0xFFB86C, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x44475A),
            lineHighlight: CodeColor(rgb: 0xF8F8F2, alpha: 0x0F) // Derived: missing line highlight background.
        )
    )
}
