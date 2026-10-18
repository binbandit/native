// Drives one running Native through the Accessibility API, for `scripts/perf/measure.sh`. Only that
// pid is touched: no keystrokes, nothing brought to the front.
//
//   drive <pid> menu <menu> <item>     presses a menu bar item, e.g. `menu File "New Session"`
//   drive <pid> prompt <text>          writes the composer's draft and presses Send
//   drive <pid> minimize               minimizes the main window
//   drive <pid> hide                   hides the app, as ⌘H does
//
// The shell running it needs the Accessibility permission. Exits non-zero when the element isn't found.
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, let pid = pid_t(arguments[0]) else {
    FileHandle.standardError.write(Data("usage: drive <pid> menu <menu> <item> | prompt <text> | minimize | hide\n".utf8))
    exit(2)
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 5)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func string(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

/// The first element under `root`, breadth first, that `matches`.
func find(_ root: AXUIElement, depth: Int = 40, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
    var level = [root]
    for _ in 0..<depth where !level.isEmpty {
        if let found = level.first(where: matches) { return found }
        level = level.flatMap(children)
    }
    return nil
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("drive: \(message)\n".utf8))
    exit(1)
}

func press(_ element: AXUIElement) {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("couldn't press") }
}

func mainWindow() -> AXUIElement {
    let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard let window = windows.first(where: { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }) else {
        fail("no window")
    }
    return window
}

switch arguments[1] {
case "menu" where arguments.count == 4:
    guard let bar = attribute(app, kAXMenuBarAttribute).map({ $0 as! AXUIElement }) else { fail("no menu bar") }
    guard let menu = children(bar).first(where: { string($0, kAXTitleAttribute) == arguments[2] }) else {
        fail("no menu \(arguments[2])")
    }
    guard let item = find(menu, depth: 3, where: { string($0, kAXTitleAttribute) == arguments[3] }) else {
        fail("no item \(arguments[3])")
    }
    press(item)
case "prompt" where arguments.count == 3:
    let window = mainWindow()
    guard
        let editor = find(window, where: {
            string($0, kAXRoleAttribute) == kAXTextAreaRole && string($0, kAXDescriptionAttribute) == "Message"
        })
    else { fail("no composer") }
    guard AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, arguments[2] as CFString) == .success
    else { fail("couldn't write the draft") }
    // The Send button appears once the draft has text.
    for _ in 0..<50 {
        if let send = find(window, where: {
            string($0, kAXRoleAttribute) == kAXButtonRole
                && (string($0, kAXDescriptionAttribute) == "Send" || string($0, kAXTitleAttribute) == "Send")
        }) {
            press(send)
            exit(0)
        }
        usleep(100_000)
    }
    fail("no Send button")
case "minimize":
    guard AXUIElementSetAttributeValue(mainWindow(), kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    else { fail("couldn't minimize") }
case "hide":
    guard AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success
    else { fail("couldn't hide") }
default:
    fail("unknown command \(arguments[1])")
}
