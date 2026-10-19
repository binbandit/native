import Foundation
import Testing

@testable import ProjectIcons

/// Files shaped like the ones projects keep: framework favicons, icon-set glyphs and editor
/// exports, drawn for these tests.
@Suite struct SVGIconTests {
    private func check(_ svg: String) throws(SVGIcon.Rejection) -> SVGIcon {
        try SVGIcon(checking: Data(svg.utf8))
    }

    private func rejection(_ svg: String) -> SVGIcon.Rejection? {
        do {
            _ = try check(svg)
            return nil
        } catch {
            return error
        }
    }

    @Test func aColorFaviconIsAPicture() throws {
        let icon = try check(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
              <defs><linearGradient id="g"><stop offset="0" stop-color="#41d1ff"/><stop offset="1" stop-color="#bd34fe"/></linearGradient></defs>
              <rect width="32" height="32" rx="6" fill="url(#g)"/>
              <path d="M8 8h16v16H8z" fill="#fff"/>
            </svg>
            """)
        #expect(!icon.isGlyph)
        #expect(icon.aspectRatio == 1)
    }

    @Test func currentColorMakesAGlyph() throws {
        let stroked = try check(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4l16 16"/></svg>
            """)
        #expect(stroked.isGlyph)
        let styled = try check(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><style>.a { fill: currentColor; }</style><path class="a" d="M0 0h16v16z"/><circle r="2" fill="#e33"/></svg>
            """)
        #expect(styled.isGlyph)
    }

    @Test func blackOnlyMakesAGlyph() throws {
        let unpainted = try check(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M1 1h4v4z"/></svg>"#)
        #expect(unpainted.isGlyph)
        let black = try check(
            ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000000" d="M1 1h4v4z" style="stroke: black !important"/></svg>"##
        )
        #expect(black.isGlyph)
        let whiteOnBlack = try check(
            ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24"/><path fill="#fff" d="M1 1h4v4z"/></svg>"##
        )
        #expect(!whiteOnBlack.isGlyph)
    }

    @Test func aspectRatioComesFromTheViewBoxThenTheSize() throws {
        #expect(try check(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0,0,120,40"/>"#).aspectRatio == 3)
        #expect(try check(#"<svg xmlns="http://www.w3.org/2000/svg" width="48px" height="24"/>"#).aspectRatio == 2)
        #expect(try check(#"<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%"/>"#).aspectRatio == nil)
    }

    @Test func editorExportsAndInternalReferencesPass() throws {
        let icon = try check(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="no"?>
            <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
            <!-- Exported -->
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
                 xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" viewBox="0 0 24 24">
              <sodipodi:namedview id="base"/>
              <title>Logo</title>
              <defs><circle id="dot" r="2"/><clipPath id="c"><rect width="12" height="12"/></clipPath></defs>
              <use xlink:href="#dot" x="4" y="4"/>
              <a href="https://example.com"><use href="#dot" x="8" y="8" clip-path="url(#c)"/></a>
            </svg>
            """)
        #expect(icon.aspectRatio == 1)
    }

    @Test func externalContentIsRejected() {
        let svg =
            #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24">"#
        #expect(rejection(svg + #"<use href="other.svg#a"/></svg>"#) == .loadsExternalContent)
        #expect(rejection(svg + #"<use xlink:href="file:///etc/hosts"/></svg>"#) == .loadsExternalContent)
        #expect(rejection(svg + #"<rect fill="url(https://example.com/p.svg#a)"/></svg>"#) == .loadsExternalContent)
        #expect(rejection(svg + #"<rect style="fill: url( 'https://x.test/a' )"/></svg>"#) == .loadsExternalContent)
        #expect(rejection(svg + #"<style>@import url("https://x.test/a.css");</style></svg>"#) == .loadsExternalContent)
        #expect(
            rejection(#"<?xml-stylesheet href="https://x.test/a.css"?><svg xmlns="http://www.w3.org/2000/svg"/>"#)
                == .loadsExternalContent)
    }

    @Test func embeddedImagesAndScriptsAreRejected() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">"#
        #expect(
            rejection(svg + #"<image href="data:image/png;base64,iVBORw0KGgo=" width="4" height="4"/></svg>"#)
                == .unsupported(element: "image"))
        #expect(rejection(svg + "<script>alert(1)</script></svg>") == .unsupported(element: "script"))
        #expect(
            rejection(svg + "<foreignObject><div xmlns=\"http://www.w3.org/1999/xhtml\"/></foreignObject></svg>")
                == .unsupported(element: "foreignObject"))
    }

    @Test func entitiesAreRejected() {
        let laughs = """
            <?xml version="1.0"?>
            <!DOCTYPE svg [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>
            <svg xmlns="http://www.w3.org/2000/svg"><text>&b;</text></svg>
            """
        #expect(rejection(laughs) == .declaresEntities)
    }

    @Test func nonSVGAndBrokenFilesAreRejected() {
        #expect(rejection("<html><body>hi</body></html>") == .notSVG)
        #expect(rejection(#"<html><svg xmlns="http://www.w3.org/2000/svg"/></html>"#) == .notSVG)
        #expect(rejection(#"<svg xmlns="http://www.w3.org/2000/svg"><rect"#) == .malformed)
    }

    @Test func hugeAndDeepFilesAreRejected() {
        let padding = String(repeating: " ", count: SVGIcon.byteLimit)
        #expect(rejection(#"<svg xmlns="http://www.w3.org/2000/svg">"# + padding + "</svg>") == .tooLarge)
        let deep =
            String(repeating: "<g>", count: SVGIcon.depthLimit + 1)
            + String(repeating: "</g>", count: SVGIcon.depthLimit + 1)
        #expect(rejection(#"<svg xmlns="http://www.w3.org/2000/svg">"# + deep + "</svg>") == .tooComplex)
        let many = String(repeating: "<rect/>", count: SVGIcon.elementLimit)
        #expect(rejection(#"<svg xmlns="http://www.w3.org/2000/svg">"# + many + "</svg>") == .tooComplex)
    }

    @Test func sniffing() {
        #expect(SVGIcon.isLikelySVG(Data("<?xml version=\"1.0\"?>\n<SVG viewBox=\"0 0 1 1\"/>".utf8)))
        #expect(!SVGIcon.isLikelySVG(Data([0x89, 0x50, 0x4E, 0x47])))
    }
}
