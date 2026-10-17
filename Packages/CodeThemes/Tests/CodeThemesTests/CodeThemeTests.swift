import CodeThemes
import Testing

@Suite("Code theme catalog")
struct CodeThemeTests {
    @Test(arguments: CodeTheme.all)
    func palettesAreComplete(_ theme: CodeTheme) {
        let variants = CodeAppearance.allCases.compactMap { appearance in
            theme.palette(for: appearance).map { (appearance, $0) }
        }
        #expect(!variants.isEmpty, "\(theme.id.rawValue) has no palette")

        for (appearance, palette) in variants {
            #expect(
                palette.background.alpha == 0xFF,
                "\(theme.id.rawValue) \(appearance.rawValue) background is not opaque"
            )
            for role in CodeTokenRole.allCases {
                #expect(
                    palette[role].alpha > 0,
                    "\(theme.id.rawValue) \(appearance.rawValue) \(role.rawValue) is transparent"
                )
            }
        }
    }

    @Test func catalogIsUniqueAndFindable() {
        let themes = CodeTheme.all
        #expect(Set(themes.map(\.id)).count == themes.count)
        #expect(Set(themes.map(\.name)).count == themes.count)
        #expect(themes.first == .native)

        for theme in themes {
            #expect(CodeTheme.theme(id: theme.id) == theme)
        }
        #expect(CodeTheme.theme(id: "unknown") == nil)
    }

    @Test(arguments: CodeTheme.all)
    func foregroundClearsAAContrast(_ theme: CodeTheme) {
        for appearance in CodeAppearance.allCases {
            guard let palette = theme.palette(for: appearance) else { continue }
            let ratio = palette.foreground.contrastRatio(with: palette.background)
            #expect(
                ratio >= 4.5,
                "\(theme.id.rawValue) \(appearance.rawValue) foreground contrast is \(ratio)"
            )
        }
    }

    @Test(arguments: CodeTheme.all)
    func diffBackgroundsRemainDistinct(_ theme: CodeTheme) {
        for appearance in CodeAppearance.allCases {
            guard let palette = theme.palette(for: appearance) else { continue }
            let inserted = palette.insertedBackground.composited(over: palette.background)
            let deleted = palette.deletedBackground.composited(over: palette.background)
            let changed = palette.changedBackground.composited(over: palette.background)

            #expect(
                differs(inserted, from: palette.background),
                "\(theme.id.rawValue) \(appearance.rawValue) inserted background is too subtle"
            )
            #expect(
                differs(deleted, from: palette.background),
                "\(theme.id.rawValue) \(appearance.rawValue) deleted background is too subtle"
            )
            #expect(
                differs(changed, from: palette.background),
                "\(theme.id.rawValue) \(appearance.rawValue) changed background is too subtle"
            )
            #expect(
                differs(inserted, from: deleted),
                "\(theme.id.rawValue) \(appearance.rawValue) inserted and deleted backgrounds match"
            )
        }
    }

    @Test func nativeTextRolesClearAAContrast() {
        for appearance in CodeAppearance.allCases {
            guard let palette = CodeTheme.native.palette(for: appearance) else {
                Issue.record("Native is missing \(appearance.rawValue)")
                continue
            }

            for role in CodeTokenRole.allCases where isTextRole(role) {
                let ratio = palette[role].contrastRatio(with: palette.background)
                #expect(ratio >= 4.5, "Native \(appearance.rawValue) \(role.rawValue) contrast is \(ratio)")
            }
        }

        #expect(CodeTheme.native.dark?.background == CodeColor(rgb: 0x171717))
    }

    private func differs(_ first: CodeColor, from second: CodeColor) -> Bool {
        abs(Int(first.red) - Int(second.red)) >= 12
            || abs(Int(first.green) - Int(second.green)) >= 12
            || abs(Int(first.blue) - Int(second.blue)) >= 12
    }

    private func isTextRole(_ role: CodeTokenRole) -> Bool {
        switch role {
        case .background, .selection, .lineHighlight, .insertedBackground, .deletedBackground, .changedBackground:
            false
        default:
            true
        }
    }
}
