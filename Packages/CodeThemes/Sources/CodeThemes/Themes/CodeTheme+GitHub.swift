extension CodeTheme {
    public static let github = CodeTheme(
        id: "github",
        name: "GitHub",
        light: CodePalette(
            // github-light.json
            foreground: CodeColor(rgb: 0x24292E),
            background: CodeColor(rgb: 0xFFFFFF),
            comment: CodeColor(rgb: 0x6A737D),
            keyword: CodeColor(rgb: 0xD73A49),
            string: CodeColor(rgb: 0x032F62),
            constant: CodeColor(rgb: 0x005CC5),
            function: CodeColor(rgb: 0x6F42C1),
            variable: CodeColor(rgb: 0xE36209),
            tag: CodeColor(rgb: 0x22863A),
            type: CodeColor(rgb: 0x6F42C1),
            operator: CodeColor(rgb: 0xD73A49),
            regex: CodeColor(rgb: 0x032F62),
            invalid: CodeColor(rgb: 0xCB2431), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0x24292E), // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x22863A),
            insertedBackground: CodeColor(rgb: 0x34D058, alpha: 0x22),
            deletedForeground: CodeColor(rgb: 0xB31D28),
            deletedBackground: CodeColor(rgb: 0xD73A49, alpha: 0x22),
            changedForeground: CodeColor(rgb: 0xE36209),
            changedBackground: CodeColor(rgb: 0xE36209, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x0366D6, alpha: 0x25),
            lineHighlight: CodeColor(rgb: 0xF6F8FA)
        ),
        dark: CodePalette(
            // github-dark.json
            foreground: CodeColor(rgb: 0xE1E4E8),
            background: CodeColor(rgb: 0x24292E),
            comment: CodeColor(rgb: 0x6A737D),
            keyword: CodeColor(rgb: 0xF97583),
            string: CodeColor(rgb: 0x9ECBFF),
            constant: CodeColor(rgb: 0x79B8FF),
            function: CodeColor(rgb: 0xB392F0),
            variable: CodeColor(rgb: 0xFFAB70),
            tag: CodeColor(rgb: 0x85E89D),
            type: CodeColor(rgb: 0xB392F0),
            operator: CodeColor(rgb: 0xF97583),
            regex: CodeColor(rgb: 0xDBEDFF),
            invalid: CodeColor(rgb: 0xF97583), // Fallback: editorError.foreground.
            punctuation: CodeColor(rgb: 0xE1E4E8), // Fallback: foreground.
            insertedForeground: CodeColor(rgb: 0x85E89D),
            insertedBackground: CodeColor(rgb: 0x28A745, alpha: 0x30),
            deletedForeground: CodeColor(rgb: 0xFDAEB7),
            deletedBackground: CodeColor(rgb: 0xD73A49, alpha: 0x30),
            changedForeground: CodeColor(rgb: 0xFFAB70),
            changedBackground: CodeColor(rgb: 0xFFAB70, alpha: 0x26), // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x3392FF, alpha: 0x44),
            lineHighlight: CodeColor(rgb: 0x2B3036)
        )
    )
}
