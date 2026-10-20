import ApplicationServices
import Foundation

/// One accessibility element and the attributes the driver reads, fetched in a single round trip.
struct Node {
    let element: AXUIElement
    /// Where it is in the snapshot it came from, which lists elements depth first.
    let index: Int
    let depth: Int
    /// The parent's index in the same snapshot.
    let parent: Int?
    let role: String
    let subrole: String?
    let title: String?
    /// `AXDescription`, where SwiftUI puts most labels.
    let label: String?
    let value: String?
    let help: String?
    let identifier: String?
    let placeholder: String?
    let enabled: Bool
    let focused: Bool
    let selected: Bool
    let frame: CGRect?

    /// Every string a query can match, identifier first.
    var texts: [String] {
        [identifier, title, label, value, help, placeholder].compactMap { $0 }
    }

    /// What a person would call it: its title, label or placeholder, else its help text.
    var name: String? {
        title ?? label ?? placeholder ?? help
    }

    var shortRole: String {
        role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    }

    /// A container with nothing of its own to say, left out of `tree` unless `--raw`.
    var isAnonymous: Bool {
        texts.isEmpty && ["AXGroup", "AXUnknown", "AXLayoutArea", "AXSplitGroup"].contains(role)
    }

    /// One line: role, name, value, identifier, state and, with `frames`, where it is.
    func describe(frames: Bool = false) -> String {
        var parts = [subrole.map { "\(role):\(Self.short($0))" } ?? role]
        if let name { parts.append(Self.quoted(name)) }
        if let label, let title, label != title { parts.append("(\(Self.quoted(label)))") }
        if let value, !value.isEmpty, value != name { parts.append("= " + Self.quoted(value)) }
        if let identifier { parts.append("#" + identifier) }
        if !enabled { parts.append("[disabled]") }
        if focused { parts.append("[focused]") }
        if selected { parts.append("[selected]") }
        if frames, let frame {
            parts.append("@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
        }
        return parts.joined(separator: " ")
    }

    private static func short(_ role: String) -> String {
        role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    }

    static func quoted(_ text: String, limit: Int = 100) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: "⏎ ")
        return "\"" + (flat.count > limit ? flat.prefix(limit) + "…" : flat) + "\""
    }
}

/// Reads accessibility trees from one process.
enum Accessibility {
    private static let attributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
        kAXHelpAttribute, kAXIdentifierAttribute, kAXPlaceholderValueAttribute, kAXEnabledAttribute,
        kAXFocusedAttribute, kAXSelectedAttribute, kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute,
    ]

    /// Every element under `roots`, depth first, in reading order. Each element is read once, since
    /// SwiftUI's trees can lead back to an element already seen, and the walk stops after `budget`
    /// seconds, telling stderr.
    static func snapshot(
        _ roots: [AXUIElement], skipping: Set<AXUIElement> = [], maxDepth: Int = 120, budget: TimeInterval = 20
    ) -> [Node] {
        var nodes: [Node] = []
        var seen = skipping
        let deadline = Date().addingTimeInterval(budget)
        var stopped = false
        func visit(_ element: AXUIElement, depth: Int, parent: Int?) {
            guard !stopped, seen.insert(element).inserted else { return }
            guard Date() < deadline else {
                stopped = true
                FileHandle.standardError.write(
                    Data(
                        "drive: read \(nodes.count) elements in \(Int(budget)) s and stopped; the rest are left out\n"
                            .utf8))
                return
            }
            var raw: CFArray?
            let options = AXCopyMultipleAttributeOptions(rawValue: 0)
            guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, options, &raw) == .success,
                let raw
            else { return }
            let values = (raw as NSArray).map { present($0 as AnyObject) }
            guard values.count == attributes.count else { return }
            let position = point(values[12])
            let size = self.size(values[13])
            nodes.append(
                Node(
                    element: element, index: nodes.count, depth: depth, parent: parent,
                    role: string(values[0]) ?? "AXUnknown", subrole: string(values[1]),
                    title: nonEmpty(string(values[2])), label: nonEmpty(string(values[3])),
                    value: text(values[4]), help: nonEmpty(string(values[5])),
                    identifier: nonEmpty(string(values[6])), placeholder: nonEmpty(string(values[7])),
                    enabled: bool(values[8]) ?? true, focused: bool(values[9]) ?? false,
                    selected: bool(values[10]) ?? false,
                    frame: position.flatMap { origin in size.map { CGRect(origin: origin, size: $0) } }))
            guard depth < maxDepth else { return }
            let index = nodes.count - 1
            for child in values[11] as? [AXUIElement] ?? [] {
                visit(child, depth: depth + 1, parent: index)
            }
        }
        for root in roots {
            visit(root, depth: 0, parent: nil)
        }
        return nodes
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
            return nil
        }
        return present(value)
    }

    static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let names else { return [] }
        return (names as NSArray).compactMap { $0 as? String }
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    /// The value as text: strings, attributed strings, numbers and booleans, URLs.
    static func text(_ value: AnyObject?) -> String? {
        switch value {
        case let string as String: string
        case let attributed as NSAttributedString: attributed.string
        case let number as NSNumber: number.stringValue
        case let url as URL: url.absoluteString
        default: nil
        }
    }

    static func point(_ value: AnyObject?) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(value), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ value: AnyObject?) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(value), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    /// nil for the error placeholders a multi-attribute read puts where an attribute is missing.
    private static func present(_ value: AnyObject) -> AnyObject? {
        if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
        {
            return nil
        }
        return CFGetTypeID(value) == CFNullGetTypeID() ? nil : value
    }

    private static func axValue(_ value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private static func string(_ value: AnyObject?) -> String? {
        value as? String
    }

    private static func bool(_ value: AnyObject?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func nonEmpty(_ text: String?) -> String? {
        text?.isEmpty == false ? text : nil
    }
}
