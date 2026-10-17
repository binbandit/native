extension CodeTheme {
    public static let rosePine = CodeTheme(
        id: "rose-pine",
        name: "Rosé Pine",
        // rose-pine-dawn.json
        light: CodePalette(
            foreground: CodeColor(rgb: 0x575279),
            background: CodeColor(rgb: 0xFAF4ED),
            comment: CodeColor(rgb: 0x9893A5),
            keyword: CodeColor(rgb: 0x286983),
            string: CodeColor(rgb: 0xEA9D34),
            constant: CodeColor(rgb: 0xD7827E),
            function: CodeColor(rgb: 0xD7827E),
            variable: CodeColor(rgb: 0xD7827E),
            tag: CodeColor(rgb: 0x56949F),
            type: CodeColor(rgb: 0x56949F),
            operator: CodeColor(rgb: 0x286983),
            regex: CodeColor(rgb: 0xEA9D34),
            invalid: CodeColor(rgb: 0xB4637A),
            punctuation: CodeColor(rgb: 0x797593),
            insertedForeground: CodeColor(rgb: 0x56949F),  // Fallback: gitDecoration.addedResourceForeground.
            insertedBackground: CodeColor(rgb: 0x56949F, alpha: 0x26),
            deletedForeground: CodeColor(rgb: 0x797593),  // Fallback: gitDecoration.deletedResourceForeground.
            deletedBackground: CodeColor(rgb: 0xB4637A, alpha: 0x26),
            changedForeground: CodeColor(rgb: 0xD7827E),  // Fallback: gitDecoration.modifiedResourceForeground.
            changedBackground: CodeColor(rgb: 0xD7827E, alpha: 0x26),  // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x6E6A86, alpha: 0x14),
            lineHighlight: CodeColor(rgb: 0x6E6A86, alpha: 0x0D)
        ),
        // rose-pine.json
        dark: CodePalette(
            foreground: CodeColor(rgb: 0xE0DEF4),
            background: CodeColor(rgb: 0x191724),
            comment: CodeColor(rgb: 0x6E6A86),
            keyword: CodeColor(rgb: 0x31748F),
            string: CodeColor(rgb: 0xF6C177),
            constant: CodeColor(rgb: 0xEBBCBA),
            function: CodeColor(rgb: 0xEBBCBA),
            variable: CodeColor(rgb: 0xEBBCBA),
            tag: CodeColor(rgb: 0x9CCFD8),
            type: CodeColor(rgb: 0x9CCFD8),
            operator: CodeColor(rgb: 0x31748F),
            regex: CodeColor(rgb: 0xF6C177),
            invalid: CodeColor(rgb: 0xEB6F92),
            punctuation: CodeColor(rgb: 0x908CAA),
            insertedForeground: CodeColor(rgb: 0x9CCFD8),  // Fallback: gitDecoration.addedResourceForeground.
            insertedBackground: CodeColor(rgb: 0x9CCFD8, alpha: 0x26),
            deletedForeground: CodeColor(rgb: 0x908CAA),  // Fallback: gitDecoration.deletedResourceForeground.
            deletedBackground: CodeColor(rgb: 0xEB6F92, alpha: 0x26),
            changedForeground: CodeColor(rgb: 0xEBBCBA),  // Fallback: gitDecoration.modifiedResourceForeground.
            changedBackground: CodeColor(rgb: 0xEBBCBA, alpha: 0x26),  // Derived: no VS Code changed-text background.
            selection: CodeColor(rgb: 0x6E6A86, alpha: 0x33),
            lineHighlight: CodeColor(rgb: 0x6E6A86, alpha: 0x1A)
        )
    )
}
