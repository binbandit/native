// Checks the composer's accessibility contract (docs/accessibility.md) against a running Native:
//
//   swift scripts/check-composer-ax.swift <pid>
//
// Open a session in that instance first. Only that process is touched, through the Accessibility
// API: no keystrokes, nothing is sent to the agent, and the draft is put back afterwards. The shell
// running it needs the Accessibility permission. Prints each check and exits non-zero if any fails.
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 2, let pid = pid_t(CommandLine.arguments[1]) else {
    print("usage: swift scripts/check-composer-ax.swift <pid>")
    exit(2)
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 5)
var failures = 0

func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    print(passed ? "pass" : "FAIL", name, terminator: detail.isEmpty ? "\n" : " (\(detail))\n")
    if !passed { failures += 1 }
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func set(_ element: AXUIElement, _ name: String, _ value: AnyObject) -> Bool {
    AXUIElementSetAttributeValue(element, name as CFString, value) == .success
}

func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(element, name as CFString, &settable)
    return settable.boolValue
}

func names(_ element: AXUIElement, parameterized: Bool) -> Set<String> {
    var names: CFArray?
    if parameterized {
        AXUIElementCopyParameterizedAttributeNames(element, &names)
    } else {
        AXUIElementCopyAttributeNames(element, &names)
    }
    return Set((names as? [String]) ?? [])
}

/// An `AXValue`, once its type ID says it is one.
func axValue(_ value: AnyObject?) -> AXValue? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXValue.self)
}

func range(_ value: AnyObject?) -> CFRange? {
    var range = CFRange()
    guard let value = axValue(value), AXValueGetValue(value, .cfRange, &range) else { return nil }
    return range
}

func rect(_ value: AnyObject?) -> CGRect? {
    var rect = CGRect.zero
    guard let value = axValue(value), AXValueGetValue(value, .cgRect, &rect) else { return nil }
    return rect
}

func parameterized(_ element: AXUIElement, _ name: String, _ parameter: AnyObject) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success
        ? value : nil
}

func axRange(_ location: Int, _ length: Int) -> AXValue? {
    var range = CFRange(location: location, length: length)
    return AXValueCreate(.cfRange, &range)
}

func first(in element: AXUIElement, where matches: (AXUIElement) -> Bool, depth: Int = 0) -> AXUIElement? {
    if matches(element) { return element }
    guard depth < 60, let children = attribute(element, "AXChildren") as? [AXUIElement] else { return nil }
    for child in children {
        if let found = first(in: child, where: matches, depth: depth + 1) { return found }
    }
    return nil
}

func find(_ matches: (AXUIElement) -> Bool) -> AXUIElement? {
    for window in (attribute(app, "AXWindows") as? [AXUIElement]) ?? [] {
        if let found = first(in: window, where: matches) { return found }
    }
    return nil
}

/// The Send button exists only while the draft has text, so it shows whether a write reached the
/// composer's state and not just the text view.
func hasSendButton() -> Bool {
    find { element in
        (attribute(element, "AXRole") as? String) == "AXButton"
            && [attribute(element, "AXTitle"), attribute(element, "AXDescription")].contains {
                $0 as? String == "Send Message"
            }
    } != nil
}

func settle() { Thread.sleep(forTimeInterval: 0.4) }

guard
    let editor = find({
        (attribute($0, "AXRole") as? String) == "AXTextArea" && (attribute($0, "AXDescription") as? String) == "Message"
    })
else {
    check("composer: an AXTextArea described \"Message\"", false, "none found; open a session first")
    exit(1)
}
check("composer: an AXTextArea described \"Message\"", true)
let original = attribute(editor, "AXValue") as? String ?? ""

let attributes = names(editor, parameterized: false)
for name in ["AXValue", "AXSelectedText", "AXSelectedTextRange", "AXFocused"] {
    check("\(name) is settable", isSettable(editor, name))
}
for name in ["AXSelectedTextRanges", "AXNumberOfCharacters", "AXInsertionPointLineNumber", "AXVisibleCharacterRange"] {
    check("\(name) is exposed", attributes.contains(name))
}
let parameterized = names(editor, parameterized: true)
for name in [
    "AXStringForRange", "AXAttributedStringForRange", "AXBoundsForRange", "AXLineForIndex", "AXRangeForLine",
    "AXRangeForPosition", "AXRangeForIndex", "AXReplaceRangeWithText",
] {
    check("\(name) is exposed", parameterized.contains(name))
}

// Writes, as a dictation tool makes them: the whole value, then text at the selection.
check("writing AXValue succeeds", set(editor, "AXValue", "contract check" as CFString))
settle()
check("AXValue reads back", attribute(editor, "AXValue") as? String == "contract check")
check("AXNumberOfCharacters follows", (attribute(editor, "AXNumberOfCharacters") as? Int) == 14)
check("an AXValue write reaches the draft (Send appears)", hasSendButton())

if let selection = axRange(0, 8) {
    check("writing AXSelectedTextRange succeeds", set(editor, "AXSelectedTextRange", selection))
}
settle()
check("AXSelectedText is the selection", attribute(editor, "AXSelectedText") as? String == "contract")
if let word = axRange(0, 8), let bounds = rect(attribute(editor, "AXFrame")),
    let selectionBounds = rect(parameterized(editor, "AXBoundsForRange", word))
{
    check(
        "AXBoundsForRange lies within the editor", bounds.insetBy(dx: -1, dy: -1).contains(selectionBounds),
        "\(selectionBounds) in \(bounds)")
}

check("writing AXSelectedText succeeds", set(editor, "AXSelectedText", "AX" as CFString))
settle()
check("AXSelectedText replaces the selection", attribute(editor, "AXValue") as? String == "AX check")
let caret = range(attribute(editor, "AXSelectedTextRange"))
check("the cursor follows the insertion", caret?.location == 2 && caret?.length == 0)

check("clearing AXValue succeeds", set(editor, "AXValue", "" as CFString))
settle()
check("clearing reaches the draft (Send goes away)", !hasSendButton())

_ = set(editor, "AXValue", original as CFString)
print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
