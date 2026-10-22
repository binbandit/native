// Drives one running Native through the Accessibility API, for `scripts/perf/measure.sh`. Only that
// pid is touched: no keystrokes, nothing brought to the front.
//
//   drive <pid> menu <menu> <item>     presses a menu bar item, e.g. `menu File "New Task"`
//   drive <pid> enabled <menu> <item>  prints whether a menu bar item is enabled (`Task Stop`
//                                      is while a turn runs)
//   drive <pid> prompt <text>          writes the composer's draft and presses Send
//   drive <pid> minimize               minimizes the main window
//   drive <pid> hide                   hides the app, as ⌘H does
//
// The shell running it needs the Accessibility permission. Exits non-zero when the element isn't found.
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, let pid = pid_t(arguments[0]) else {
    FileHandle.standardError.write(
        Data("usage: drive <pid> menu <menu> <item> | prompt <text> | minimize | hide\n".utf8))
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

func menuItem(_ menuTitle: String, _ itemTitle: String) -> AXUIElement {
    guard let value = attribute(app, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
        fail("no menu bar")
    }
    let bar = unsafeBitCast(value, to: AXUIElement.self)
    guard let menu = children(bar).first(where: { string($0, kAXTitleAttribute) == menuTitle }) else {
        fail("no menu \(menuTitle)")
    }
    guard let item = find(menu, depth: 3, where: { string($0, kAXTitleAttribute) == itemTitle }) else {
        fail("no item \(itemTitle)")
    }
    return item
}

switch arguments[1] {
case "menu" where arguments.count == 4:
    press(menuItem(arguments[2], arguments[3]))
case "enabled" where arguments.count == 4:
    print((attribute(menuItem(arguments[2], arguments[3]), kAXEnabledAttribute) as? Bool) == true)
case "prompt" where arguments.count == 3:
    let window = mainWindow()
    guard
        let editor = find(
            window,
            where: {
                string($0, kAXRoleAttribute) == kAXTextAreaRole && string($0, kAXDescriptionAttribute) == "Message"
            })
    else { fail("no composer") }
    guard AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, arguments[2] as CFString) == .success
    else { fail("couldn't write the draft") }
    // The Send button appears once the draft has text.
    for _ in 0..<50 {
        if let send = find(
            window,
            where: {
                string($0, kAXRoleAttribute) == kAXButtonRole
                    && string($0, kAXDescriptionAttribute) == "Send Message"
            })
        {
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
