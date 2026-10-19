import Foundation

/// An SVG Native draws as a project icon. It's checked before any renderer sees it, because the
/// platform's renderer draws a broken-image cross instead of failing on a file it can't handle,
/// and follows references to other files and addresses. So an `SVGIcon` is small, self-contained
/// (nothing outside the file is loaded) and made only of elements that renderer draws.
public struct SVGIcon: Hashable, Sendable {
    /// The file, unchanged.
    public let data: Data
    /// Whether it's drawn in one color, the foreground of wherever it's shown: it paints with
    /// `currentColor`, or only in black, which would vanish on a dark background.
    public let isGlyph: Bool
    /// Width over height, from the `viewBox` or else `width` and `height`; nil when the file gives
    /// neither.
    public let aspectRatio: Double?

    /// Icons are a few kilobytes; a file past this isn't one.
    public static let byteLimit = 512 * 1024
    /// Elements and nesting a file may have, so a pathological one can't stall drawing.
    public static let elementLimit = 10_000
    public static let depthLimit = 64

    public init(checking data: Data) throws(Rejection) {
        guard data.count <= Self.byteLimit else { throw .tooLarge }
        let text = String(decoding: data, as: UTF8.self).lowercased()
        guard text.contains("<svg") else { throw .notSVG }
        // Entities can expand without bound; no icon needs them.
        guard !text.contains("<!entity") else { throw .declaresEntities }
        let checker = SVGChecker()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = checker
        let parsed = parser.parse()
        if let rejection = checker.rejection { throw rejection }
        guard parsed else { throw .malformed }
        guard checker.hasRoot else { throw .notSVG }
        self.data = data
        isGlyph = checker.usesCurrentColor || checker.paintsOnlyBlack
        aspectRatio = checker.aspectRatio
    }

    /// Whether the bytes look like an SVG, for files picked without a type that says so.
    public static func isLikelySVG(_ data: Data) -> Bool {
        String(decoding: data.prefix(4096), as: UTF8.self).lowercased().contains("<svg")
    }

    /// Why a file can't be a project icon.
    public enum Rejection: Error, Hashable, Sendable {
        case tooLarge
        case notSVG
        case malformed
        case declaresEntities
        /// It links to other files, addresses or stylesheets.
        case loadsExternalContent
        /// An element the renderer doesn't draw, or that runs or embeds something.
        case unsupported(element: String)
        case tooComplex

        /// The reason, as a sentence that follows "Native can't use that SVG."
        public var reason: String {
            switch self {
            case .tooLarge: "It's larger than \(SVGIcon.byteLimit / 1024) KB, which is too big for an icon."
            case .notSVG: "It isn't an SVG file."
            case .malformed: "It isn't valid XML."
            case .declaresEntities: "It declares XML entities, which icons can't use."
            case .loadsExternalContent: "It loads other files or web addresses, which icons can't do."
            case .unsupported(let element): "It uses <\(element)>, which icons can't draw."
            case .tooComplex:
                "It has more than \(SVGIcon.elementLimit.formatted()) elements or nests them too deeply to draw as an icon."
            }
        }
    }
}

/// Walks the file once: rejects what the renderer can't draw or would load from elsewhere, and
/// notes how it's painted and shaped.
private final class SVGChecker: NSObject, XMLParserDelegate {
    private(set) var rejection: SVGIcon.Rejection?
    private(set) var hasRoot = false
    private(set) var usesCurrentColor = false
    private(set) var paintsOnlyBlack = true
    private(set) var aspectRatio: Double?
    private var elements = 0
    private var depth = 0
    private var style: String?

    private static let svgNamespace = "http://www.w3.org/2000/svg"
    /// Elements that embed other documents, run code or play media. The renderer draws a broken
    /// image for `image`, and `feImage` and `use` can load other files too (`use` may only point
    /// inside the file, which the href check makes sure of).
    private static let unsupported: Set<String> = [
        "image", "feImage", "script", "foreignObject", "iframe", "video", "audio", "canvas", "object", "embed",
    ]
    private static let paintProperties: Set<String> = ["fill", "stroke", "stop-color", "flood-color", "lighting-color"]
    private static let neutralPaints: Set<String> = [
        "none", "currentcolor", "black", "#000", "#000f", "#000000", "#000000ff", "transparent", "inherit", "initial",
        "unset", "rgb(0,0,0)", "rgba(0,0,0,1)",
    ]

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        elements += 1
        depth += 1
        guard elements <= SVGIcon.elementLimit, depth <= SVGIcon.depthLimit else { return reject(.tooComplex, parser) }
        let isSVG = namespaceURI.map { $0.isEmpty || $0 == Self.svgNamespace } ?? true
        if !hasRoot {
            hasRoot = true
            guard isSVG, elementName == "svg" else { return reject(.notSVG, parser) }
            aspectRatio = Self.aspectRatio(of: attributes)
        }
        if isSVG, Self.unsupported.contains(elementName) {
            return reject(.unsupported(element: elementName), parser)
        }
        for (name, value) in attributes {
            if name == "href" || name.hasSuffix(":href") {
                // A link is followed only when clicked, which an icon never is; everything else
                // that references must stay inside the file.
                if elementName != "a", !value.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    return reject(.loadsExternalContent, parser)
                }
            } else if name == "style" {
                inspect(css: value)
            } else {
                inspect(property: name, value: value)
            }
        }
        if elementName == "style" { style = "" }
        if let rejection { reject(rejection, parser) }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        depth -= 1
        if elementName == "style", let css = style {
            style = nil
            inspect(css: css)
            if let rejection { reject(rejection, parser) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        style?.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        style?.append(String(decoding: block, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        if target == "xml-stylesheet" { reject(.loadsExternalContent, parser) }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        reject(.declaresEntities, parser)
    }

    func parser(
        _ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?,
        systemID: String?
    ) {
        reject(.declaresEntities, parser)
    }

    private func reject(_ reason: SVGIcon.Rejection, _ parser: XMLParser) {
        if rejection == nil { rejection = reason }
        parser.abortParsing()
    }

    /// A presentation attribute: notes `currentColor`, colors and references.
    private func inspect(property name: String, value: String) {
        let value = value.lowercased()
        if value.contains("currentcolor") { usesCurrentColor = true }
        if !Self.referencesStayInside(value) { rejection = rejection ?? .loadsExternalContent }
        if Self.paintProperties.contains(name), !Self.isNeutral(value) { paintsOnlyBlack = false }
    }

    /// A `style` attribute or element: the same, declaration by declaration, plus `@import`.
    private func inspect(css: String) {
        let css = css.lowercased()
        if css.contains("@import") { rejection = rejection ?? .loadsExternalContent }
        // Selectors and blocks come apart on the braces, declarations on the semicolons; anything
        // without a colon is a selector.
        for declaration in css.split(whereSeparator: { $0 == ";" || $0 == "{" || $0 == "}" }) {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            inspect(property: parts[0].trimmingCharacters(in: .whitespacesAndNewlines), value: String(parts[1]))
        }
    }

    /// Whether every `url(…)` in the value points inside the file (`url(#gradient)`).
    private static func referencesStayInside(_ value: String) -> Bool {
        var rest = value[...]
        while let range = rest.range(of: "url(") {
            let target = rest[range.upperBound...].drop { $0 == " " || $0 == "'" || $0 == "\"" }
            guard target.first == "#" else { return false }
            rest = target
        }
        return true
    }

    private static func isNeutral(_ paint: String) -> Bool {
        let compact = paint.replacing("!important", with: "").filter { !$0.isWhitespace }
        return neutralPaints.contains(compact)
    }

    private static func aspectRatio(of attributes: [String: String]) -> Double? {
        if let viewBox = attributes["viewBox"] {
            let numbers = viewBox.split(whereSeparator: { $0 == " " || $0 == "," || $0.isNewline })
                .compactMap { Double($0) }
            if numbers.count == 4, numbers[2] > 0, numbers[3] > 0 { return numbers[2] / numbers[3] }
        }
        guard let width = attributes["width"].flatMap(length), let height = attributes["height"].flatMap(length),
            width > 0, height > 0
        else { return nil }
        return width / height
    }

    /// An absolute length ("24", "24px"); percentages depend on where the file is shown.
    private static func length(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasSuffix("%") else { return nil }
        return Double(trimmed.prefix { $0.isNumber || $0 == "." })
    }
}
