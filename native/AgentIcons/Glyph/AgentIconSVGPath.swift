import CoreGraphics

/// Turns SVG path data (`M1 1H11V8Z`) into a `CGPath`: every command, absolute and relative, with
/// implicit repeats and the compact forms exporters write (`1.5.5`, `-1-2`, arc flags run together).
nonisolated enum AgentIconSVGPath {
    /// Nil when the data is malformed: a half-drawn icon looks worse than the fallback.
    static func path(from data: String) -> CGPath? {
        var scanner = AgentIconSVGScanner(data)
        var builder = Builder()
        var command: UInt8?
        while !scanner.isAtEnd {
            if let next = scanner.command() {
                command = next
            } else if command == nil || !scanner.startsNumber {
                return nil
            }
            guard let current = command, builder.apply(current, from: &scanner) else { return nil }
            // After a moveto, more coordinate pairs are linetos; closepath takes no parameters.
            switch current {
            case UInt8(ascii: "M"): command = UInt8(ascii: "L")
            case UInt8(ascii: "m"): command = UInt8(ascii: "l")
            case UInt8(ascii: "Z"), UInt8(ascii: "z"): command = nil
            default: break
            }
        }
        return builder.path.isEmpty ? nil : builder.path
    }

    /// The path so far, the pen, and what the smooth curves reflect.
    private struct Builder {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        /// Reads one command's parameters and draws it. False when they're missing or malformed.
        mutating func apply(_ command: UInt8, from scanner: inout AgentIconSVGScanner) -> Bool {
            let relative = command >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            var cubicControl: CGPoint?
            var quadControl: CGPoint?
            switch command | 0x20 {
            case UInt8(ascii: "m"):
                guard let point = scanner.point(offset: origin) else { return false }
                path.move(to: point)
                current = point
                subpathStart = point
            case UInt8(ascii: "l"):
                guard let point = scanner.point(offset: origin) else { return false }
                line(to: point)
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return false }
                line(to: CGPoint(x: x + origin.x, y: current.y))
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return false }
                line(to: CGPoint(x: current.x, y: y + origin.y))
            case UInt8(ascii: "c"):
                guard let first = scanner.point(offset: origin), let second = scanner.point(offset: origin),
                    let end = scanner.point(offset: origin)
                else { return false }
                curve(to: end, first, second)
                cubicControl = second
            case UInt8(ascii: "s"):
                guard let second = scanner.point(offset: origin), let end = scanner.point(offset: origin) else {
                    return false
                }
                curve(to: end, reflected(lastCubicControl), second)
                cubicControl = second
            case UInt8(ascii: "q"):
                guard let control = scanner.point(offset: origin), let end = scanner.point(offset: origin) else {
                    return false
                }
                quadCurve(to: end, control)
                quadControl = control
            case UInt8(ascii: "t"):
                guard let end = scanner.point(offset: origin) else { return false }
                let control = reflected(lastQuadControl)
                quadCurve(to: end, control)
                quadControl = control
            case UInt8(ascii: "a"):
                guard let radiusX = scanner.number(), let radiusY = scanner.number(), let rotation = scanner.number(),
                    let largeArc = scanner.flag(), let sweep = scanner.flag(), let end = scanner.point(offset: origin)
                else { return false }
                arc(to: end, radius: CGSize(width: radiusX, height: radiusY), rotation: rotation, largeArc: largeArc, sweep: sweep)
            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
            default:
                return false
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
            return true
        }

        private func reflected(_ control: CGPoint?) -> CGPoint {
            guard let control else { return current }
            return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
        }

        private mutating func line(to point: CGPoint) {
            path.addLine(to: point)
            current = point
        }

        private mutating func curve(to end: CGPoint, _ first: CGPoint, _ second: CGPoint) {
            path.addCurve(to: end, control1: first, control2: second)
            current = end
        }

        private mutating func quadCurve(to end: CGPoint, _ control: CGPoint) {
            path.addQuadCurve(to: end, control: control)
            current = end
        }

        /// SVG's endpoint arc, converted to a center arc (SVG 1.1, appendix F.6.5) and drawn on a unit
        /// circle stretched and rotated into the ellipse.
        private mutating func arc(to end: CGPoint, radius: CGSize, rotation: CGFloat, largeArc: Bool, sweep: Bool) {
            defer { current = end }
            var radiusX = abs(radius.width)
            var radiusY = abs(radius.height)
            guard end != current else { return }
            guard radiusX > 0, radiusY > 0 else { return path.addLine(to: end) }
            let angle = rotation * .pi / 180
            let (cosine, sine) = (cos(angle), sin(angle))
            let halfX = (current.x - end.x) / 2
            let halfY = (current.y - end.y) / 2
            let x1 = cosine * halfX + sine * halfY
            let y1 = -sine * halfX + cosine * halfY
            // Radii too small to reach the end point grow just enough to.
            let scale = (x1 * x1) / (radiusX * radiusX) + (y1 * y1) / (radiusY * radiusY)
            if scale > 1 {
                radiusX *= scale.squareRoot()
                radiusY *= scale.squareRoot()
            }
            let rx2 = radiusX * radiusX
            let ry2 = radiusY * radiusY
            let denominator = rx2 * y1 * y1 + ry2 * x1 * x1
            let root = (max(0, (rx2 * ry2 - denominator) / denominator)).squareRoot() * (largeArc == sweep ? -1 : 1)
            let centerX1 = root * radiusX * y1 / radiusY
            let centerY1 = -root * radiusY * x1 / radiusX
            let center = CGPoint(
                x: cosine * centerX1 - sine * centerY1 + (current.x + end.x) / 2,
                y: sine * centerX1 + cosine * centerY1 + (current.y + end.y) / 2
            )
            let start = CGVector(dx: (x1 - centerX1) / radiusX, dy: (y1 - centerY1) / radiusY)
            let finish = CGVector(dx: (-x1 - centerX1) / radiusX, dy: (-y1 - centerY1) / radiusY)
            let startAngle = Self.angle(from: CGVector(dx: 1, dy: 0), to: start)
            var delta = Self.angle(from: start, to: finish)
            if !sweep, delta > 0 { delta -= 2 * .pi }
            if sweep, delta < 0 { delta += 2 * .pi }
            let ellipse = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .scaledBy(x: radiusX, y: radiusY)
            path.addRelativeArc(center: .zero, radius: 1, startAngle: startAngle, delta: delta, transform: ellipse)
        }

        private static func angle(from first: CGVector, to second: CGVector) -> CGFloat {
            atan2(first.dx * second.dy - first.dy * second.dx, first.dx * second.dx + first.dy * second.dy)
        }
    }
}

/// Reads SVG's number lists: separators are optional wherever a sign, a second decimal point or a
/// command letter already ends the number.
nonisolated struct AgentIconSVGScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    var isAtEnd: Bool {
        mutating get {
            skipSeparators()
            return index >= bytes.count
        }
    }

    /// Whether a number comes next.
    var startsNumber: Bool {
        mutating get {
            skipSeparators()
            guard index < bytes.count else { return false }
            let byte = bytes[index]
            return Self.isDigit(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
        }
    }

    /// The next command letter, consumed; nil when a number (or nothing) comes next.
    mutating func command() -> UInt8? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        let byte = bytes[index]
        guard (byte | 0x20) >= UInt8(ascii: "a"), (byte | 0x20) <= UInt8(ascii: "z"), byte != UInt8(ascii: "e"),
            byte != UInt8(ascii: "E")
        else { return nil }
        index += 1
        return byte
    }

    mutating func point(offset: CGPoint) -> CGPoint? {
        guard let x = number(), let y = number() else { return nil }
        return CGPoint(x: x + offset.x, y: y + offset.y)
    }

    /// An arc flag: a single 0 or 1, which may run straight into the next number (`a1 1 0 01 2 2`).
    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "0"): index += 1; return false
        case UInt8(ascii: "1"): index += 1; return true
        default: return nil
        }
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
        let integerDigits = consumeDigits()
        var fractionDigits = 0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            fractionDigits = consumeDigits()
        }
        guard integerDigits + fractionDigits > 0 else {
            index = start
            return nil
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            let mantissaEnd = index
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
            if consumeDigits() == 0 { index = mantissaEnd }
        }
        guard let text = String(bytes: bytes[start..<index], encoding: .ascii), let value = Double(text) else {
            return nil
        }
        return CGFloat(value)
    }

    private mutating func consumeDigits() -> Int {
        let start = index
        while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
        return index - start
    }

    private mutating func skipSeparators() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D, 0x0C, UInt8(ascii: ","): index += 1
            default: return
            }
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
}
