extension CodeTheme {
    public static let gruvboxDark = CodeTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        // gruvbox-dark-medium.json
        dark: CodePalette(
            foreground: CodeColor(rgb: 0xEBDBB2),
            background: CodeColor(rgb: 0x282828),
            comment: CodeColor(rgb: 0x928374),
            keyword: CodeColor(rgb: 0xFB4934),
            string: CodeColor(rgb: 0xB8BB26),
            constant: CodeColor(rgb: 0xD3869B),
            function: CodeColor(rgb: 0xFABD2F),
            variable: CodeColor(rgb: 0x83A598),
            tag: CodeColor(rgb: 0x8EC07C),
            type: CodeColor(rgb: 0xFABD2F),
            operator: CodeColor(rgb: 0x8EC07C),
            regex: CodeColor(rgb: 0xFE8019),
            invalid: CodeColor(rgb: 0xCC241D),
            punctuation: CodeColor(rgb: 0xA89984),
            insertedForeground: CodeColor(rgb: 0xB8BB26),
            insertedBackground: CodeColor(rgb: 0xB8BB26, alpha: 0x30),
            deletedForeground: CodeColor(rgb: 0xD65D0E),
            deletedBackground: CodeColor(rgb: 0xFB4934, alpha: 0x30),
            changedForeground: CodeColor(rgb: 0xFE8019),
            changedBackground: CodeColor(rgb: 0xFE8019, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x689D6A, alpha: 0x40),
            lineHighlight: CodeColor(rgb: 0x3C3836, alpha: 0x60)
        )
    )
}
