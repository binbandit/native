extension CodeTheme {
    public static let tokyoNight = CodeTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        dark: CodePalette(
            // tokyo-night.json
            foreground: CodeColor(rgb: 0xA9B1D6),
            background: CodeColor(rgb: 0x1A1B26),
            comment: CodeColor(rgb: 0x51597D),
            keyword: CodeColor(rgb: 0xBB9AF7),
            string: CodeColor(rgb: 0x9ECE6A),
            constant: CodeColor(rgb: 0xFF9E64),
            function: CodeColor(rgb: 0x7AA2F7),
            variable: CodeColor(rgb: 0xC0CAF5),
            tag: CodeColor(rgb: 0xF7768E),
            type: CodeColor(rgb: 0xC0CAF5),
            operator: CodeColor(rgb: 0x89DDFF),
            regex: CodeColor(rgb: 0xB4F9F8),
            invalid: CodeColor(rgb: 0xFF5370),
            punctuation: CodeColor(rgb: 0x89DDFF),
            insertedForeground: CodeColor(rgb: 0x449DAB),
            insertedBackground: CodeColor(rgb: 0x41A6B5, alpha: 0x20),
            deletedForeground: CodeColor(rgb: 0x914C54),
            deletedBackground: CodeColor(rgb: 0xDB4B4B, alpha: 0x22),
            changedForeground: CodeColor(rgb: 0x6183BB),
            changedBackground: CodeColor(rgb: 0x6183BB, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x515C7E, alpha: 0x4D),
            lineHighlight: CodeColor(rgb: 0x1E202E)
        )
    )
}
