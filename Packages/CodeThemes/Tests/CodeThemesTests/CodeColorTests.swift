import CodeThemes
import Testing

@Suite("Code color")
struct CodeColorTests {
    @Test func contrastRatiosFollowWCAG() {
        let black = CodeColor(rgb: 0x000000)
        let white = CodeColor(rgb: 0xFFFFFF)

        #expect(abs(white.contrastRatio(with: black) - 21) < 0.01)
        #expect(black.contrastRatio(with: black) == 1)
    }

    @Test func descriptionUsesUppercaseHex() {
        #expect(CodeColor(rgb: 0xABCDEF).description == "#ABCDEF")
        #expect(CodeColor(rgb: 0x010203, alpha: 0x45).description == "#01020345")
    }

    @Test func compositingUsesSourceOverAlpha() {
        let color = CodeColor(red: 0xFF, green: 0, blue: 0, alpha: 0x80).composited(over: CodeColor(rgb: 0x0000FF))

        #expect(color == CodeColor(red: 0x80, green: 0, blue: 0x7F))
    }
}
