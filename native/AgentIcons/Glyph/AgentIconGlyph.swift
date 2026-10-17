import CoreGraphics
import Foundation

/// A monochrome vector icon, drawn in whatever color the text around it uses, like an SF Symbol.
/// It's how the ACP registry ships agent icons: a 16×16 SVG that fills with `currentColor`.
nonisolated struct AgentIconGlyph {
    /// One filled shape. Shapes keep their own fill rule, so one glyph can mix them.
    struct Piece {
        /// In the glyph's own coordinates (`viewBox`).
        let path: CGPath
        let evenOdd: Bool
        let opacity: Double
    }

    let pieces: [Piece]
    /// The area the artwork was drawn for, which scales to the space the glyph is given.
    let viewBox: CGRect

    /// Reads an SVG, or nil when it isn't one or uses something a glyph can't draw (text, images,
    /// external references), so a monogram stands in rather than a broken icon.
    init?(svg data: Data) {
        let reader = AgentIconSVGReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !reader.isUnsupported, !reader.pieces.isEmpty else { return nil }
        let bounds = reader.pieces.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        guard let viewBox = reader.viewBox ?? (bounds.isNull ? nil : bounds), viewBox.width > 0, viewBox.height > 0
        else { return nil }
        self.pieces = reader.pieces
        self.viewBox = viewBox
    }
}

/// Walks the SVG's elements, keeping the inherited presentation attributes of each group, and
/// turns every shape into a filled piece (strokes become their outline).
nonisolated private final class AgentIconSVGReader: NSObject, XMLParserDelegate {
    /// Presentation attributes, inherited by children.
    private struct Style {
        var fills = true
        var evenOdd = false
        var strokes = false
        var strokeWidth: CGFloat = 1
        var lineCap = CGLineCap.butt
        var lineJoin = CGLineJoin.miter
        var opacity = 1.0
        var fillOpacity = 1.0
        var transform = CGAffineTransform.identity
    }

    private(set) var pieces: [AgentIconGlyph.Piece] = []
    private(set) var viewBox: CGRect?
    private(set) var isUnsupported = false

    private var styles = [Style()]
    /// How deep inside an element whose content isn't drawn (definitions, metadata) the reader is.
    private var skippedDepth = 0
    private var sawRoot = false

    /// Content that is never drawn directly.
    private static let skipped: Set = [
        "defs", "clipPath", "mask", "symbol", "title", "desc", "metadata", "style", "linearGradient",
        "radialGradient", "pattern", "filter", "marker",
    ]
    /// Content a glyph can't reproduce faithfully.
    private static let unsupported: Set = ["text", "image", "use", "foreignObject", "switch"]

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard skippedDepth == 0 else {
            skippedDepth += 1
            return
        }
        if Self.skipped.contains(name) || Self.unsupported.contains(name) {
            isUnsupported = isUnsupported || Self.unsupported.contains(name)
            skippedDepth = 1
            return
        }
        let attributes = Self.merged(attributes)
        let style = Self.style(attributes, inheriting: styles.last ?? Style())
        styles.append(style)
        if name == "svg", !sawRoot {
            sawRoot = true
            viewBox = Self.viewBox(attributes)
        }
        guard let shape = Self.shape(name, attributes) else { return }
        if style.fills {
            pieces.append(.init(path: transformed(shape, style), evenOdd: style.evenOdd, opacity: style.opacity * style.fillOpacity))
        }
        if style.strokes, style.strokeWidth > 0 {
            let outline = shape.copy(strokingWithWidth: style.strokeWidth, lineCap: style.lineCap, lineJoin: style.lineJoin, miterLimit: 4)
            pieces.append(.init(path: transformed(outline, style), evenOdd: false, opacity: style.opacity))
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if skippedDepth > 0 {
            skippedDepth -= 1
        } else if styles.count > 1 {
            styles.removeLast()
        }
    }

    private func transformed(_ path: CGPath, _ style: Style) -> CGPath {
        var transform = style.transform
        return path.copy(using: &transform) ?? path
    }

    // MARK: - Attributes

    /// The element's attributes with its `style="fill:none;…"` declarations folded in, which win.
    private static func merged(_ attributes: [String: String]) -> [String: String] {
        guard let declarations = attributes["style"] else { return attributes }
        var merged = attributes
        for declaration in declarations.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { merged[parts[0]] = parts[1] }
        }
        return merged
    }

    private static func style(_ attributes: [String: String], inheriting parent: Style) -> Style {
        var style = parent
        if let fill = attributes["fill"] { style.fills = fill != "none" && fill != "transparent" }
        if let rule = attributes["fill-rule"] { style.evenOdd = rule == "evenodd" }
        if let stroke = attributes["stroke"] { style.strokes = stroke != "none" && stroke != "transparent" }
        if let width = number(attributes["stroke-width"]) { style.strokeWidth = width }
        switch attributes["stroke-linecap"] {
        case "round": style.lineCap = .round
        case "square": style.lineCap = .square
        case "butt": style.lineCap = .butt
        default: break
        }
        switch attributes["stroke-linejoin"] {
        case "round": style.lineJoin = .round
        case "bevel": style.lineJoin = .bevel
        case "miter": style.lineJoin = .miter
        default: break
        }
        // Opacity multiplies down the tree; fill-opacity is inherited as is.
        style.opacity = parent.opacity * (number(attributes["opacity"]).map(Double.init) ?? 1)
        if let fillOpacity = number(attributes["fill-opacity"]) { style.fillOpacity = Double(fillOpacity) }
        if let transform = attributes["transform"].flatMap(AgentIconSVGTransform.parse) {
            // The element's own transform applies first, then its parents'.
            style.transform = transform.concatenating(parent.transform)
        }
        return style
    }

    private static func viewBox(_ attributes: [String: String]) -> CGRect? {
        if let values = attributes["viewBox"].map(numbers), values.count == 4 {
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        guard let width = number(attributes["width"]), let height = number(attributes["height"]) else { return nil }
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private static func shape(_ name: String, _ attributes: [String: String]) -> CGPath? {
        func value(_ key: String) -> CGFloat { number(attributes[key]) ?? 0 }
        switch name {
        case "path":
            return attributes["d"].flatMap(AgentIconSVGPath.path)
        case "rect":
            let rect = CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height"))
            guard rect.width > 0, rect.height > 0 else { return nil }
            // A missing radius takes the other's value; both are capped at half the side.
            let radiusX = number(attributes["rx"]) ?? number(attributes["ry"]) ?? 0
            let radiusY = number(attributes["ry"]) ?? radiusX
            return CGPath(
                roundedRect: rect, cornerWidth: min(radiusX, rect.width / 2), cornerHeight: min(radiusY, rect.height / 2),
                transform: nil)
        case "circle":
            let radius = value("r")
            guard radius > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: value("cx") - radius, y: value("cy") - radius, width: radius * 2, height: radius * 2), transform: nil)
        case "ellipse":
            let (radiusX, radiusY) = (value("rx"), value("ry"))
            guard radiusX > 0, radiusY > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: value("cx") - radiusX, y: value("cy") - radiusY, width: radiusX * 2, height: radiusY * 2), transform: nil)
        case "line":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: value("x1"), y: value("y1")))
            path.addLine(to: CGPoint(x: value("x2"), y: value("y2")))
            return path
        case "polyline", "polygon":
            let values = attributes["points"].map(numbers) ?? []
            let points = stride(from: 0, to: values.count - 1, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
            guard points.count > 1 else { return nil }
            let path = CGMutablePath()
            path.addLines(between: points)
            if name == "polygon" { path.closeSubpath() }
            return path
        default:
            return nil
        }
    }

    /// A length in user units; `px` is the same thing, and anything relative (`%`, `em`) is unknown.
    private static func number(_ text: String?) -> CGFloat? {
        guard var text = text?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasSuffix("px") { text.removeLast(2) }
        return Double(text).map { CGFloat($0) }
    }

    private static func numbers(_ text: String) -> [CGFloat] {
        var scanner = AgentIconSVGScanner(text)
        var values: [CGFloat] = []
        while let value = scanner.number() { values.append(value) }
        return values
    }
}

/// SVG's `transform` attribute: a list like `translate(2 2) rotate(45 8 8)`, applied right to left.
nonisolated enum AgentIconSVGTransform {
    static func parse(_ text: String) -> CGAffineTransform? {
        var result = CGAffineTransform.identity
        for function in text.split(separator: ")") {
            let parts = function.split(separator: "(", maxSplits: 1)
            guard parts.count == 2 else {
                if function.allSatisfy({ $0.isWhitespace || $0 == "," }) { continue }
                return nil
            }
            var scanner = AgentIconSVGScanner(String(parts[1]))
            var values: [CGFloat] = []
            while let value = scanner.number() { values.append(value) }
            guard let transform = make(parts[0].trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ","))), values)
            else { return nil }
            // Later functions in the list apply to the point first.
            result = transform.concatenating(result)
        }
        return result
    }

    private static func make(_ name: String, _ values: [CGFloat]) -> CGAffineTransform? {
        switch (name, values.count) {
        case ("matrix", 6):
            return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
        case ("translate", 1), ("translate", 2):
            return CGAffineTransform(translationX: values[0], y: values.count == 2 ? values[1] : 0)
        case ("scale", 1), ("scale", 2):
            return CGAffineTransform(scaleX: values[0], y: values.count == 2 ? values[1] : values[0])
        case ("rotate", 1):
            return CGAffineTransform(rotationAngle: values[0] * .pi / 180)
        case ("rotate", 3):
            return CGAffineTransform(translationX: values[1], y: values[2])
                .rotated(by: values[0] * .pi / 180)
                .translatedBy(x: -values[1], y: -values[2])
        case ("skewX", 1):
            return CGAffineTransform(a: 1, b: 0, c: tan(values[0] * .pi / 180), d: 1, tx: 0, ty: 0)
        case ("skewY", 1):
            return CGAffineTransform(a: 1, b: tan(values[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
        default:
            return nil
        }
    }
}
