// Scrolls one running Native's transcript through the Accessibility API, by setting the transcript's
// vertical scroll bar 120 times a second, for measuring long transcripts (docs/performance.md, "Long
// transcripts"). Only that pid is touched: no events, no cursor, nothing comes to the front.
//
//   scroll <pid> travel                     how far the whole scroll bar scrolls, in points
//   scroll <pid> velocity <points/s> <s>    from where it is, up at that speed for half the time, then
//                                           back down
//   scroll <pid> sweep <s>                  bottom to top and back, evenly: every frame all new rows
//   scroll <pid> set <0…1>                  0 is the top, 1 the bottom
//
// The transcript is the window's widest scroll area. A lazy stack only knows its rows' heights
// estimated, so `travel` (and the speed `velocity` keeps) is approximate. The shell running it needs
// the Accessibility permission.
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, let pid = pid_t(arguments[0]) else {
    FileHandle.standardError.write(
        Data("usage: scroll <pid> travel | velocity <points/s> <s> | sweep <s> | set <0…1>\n".utf8))
    exit(2)
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 5)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func frame(_ element: AXUIElement) -> CGRect {
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
        AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &origin)
    }
    if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
        AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size)
    }
    return CGRect(origin: origin, size: size)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("scroll: \(message)\n".utf8))
    exit(1)
}

/// The widest scroll area in the app.
func transcript() -> AXUIElement? {
    var best: (element: AXUIElement, width: CGFloat)?
    func walk(_ element: AXUIElement, depth: Int) {
        if (attribute(element, kAXRoleAttribute) as? String) == kAXScrollAreaRole {
            let width = frame(element).width
            if width > (best?.width ?? 0) { best = (element, width) }
            return
        }
        guard depth < 40 else { return }
        for child in children(element) { walk(child, depth: depth + 1) }
    }
    walk(app, depth: 0)
    return best?.element
}

guard let area = transcript() else { fail("no scroll area") }
guard let barValue = attribute(area, kAXVerticalScrollBarAttribute), CFGetTypeID(barValue) == AXUIElementGetTypeID()
else { fail("no scroll bar") }
let bar = unsafeBitCast(barValue, to: AXUIElement.self)

func value() -> Double {
    (attribute(bar, kAXValueAttribute) as? NSNumber)?.doubleValue ?? 0
}

func set(_ value: Double) {
    AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: min(max(value, 0), 1)))
}

/// The scroll bar's whole range in points: a small step up moves the rows on screen by the step's share
/// of it.
func travel() -> Double {
    let rows = { children(area).map(frame).first { $0.width > 300 && $0.height > 0 } ?? .zero }
    let start = value()
    let before = rows()
    let step = 0.001
    set(start - step)
    usleep(300_000)
    let moved = Double(rows().maxY - before.maxY)
    set(start)
    usleep(300_000)
    return moved / step
}

/// Calls `move` with each step's fraction of the way, 120 times a second, keeping to the clock.
func drive(seconds: Double, _ move: (Int, Int) -> Void) -> TimeInterval {
    let tick = 1.0 / 120
    let steps = Int(seconds / tick)
    let start = Date()
    for step in 0..<steps {
        move(step, steps)
        let wait = start.addingTimeInterval(Double(step + 1) * tick).timeIntervalSinceNow
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
    }
    return -start.timeIntervalSinceNow
}

switch arguments[1] {
case "travel":
    print(Int(travel()))
case "set" where arguments.count == 3:
    set(Double(arguments[2]) ?? 1)
case "velocity" where arguments.count == 4:
    let speed = Double(arguments[2]) ?? 4000
    let seconds = Double(arguments[3]) ?? 10
    let range = max(travel(), 1)
    var position = value()
    let took = drive(seconds: seconds) { step, steps in
        position += (step < steps / 2 ? -1 : 1) * speed / 120 / range
        set(position)
    }
    // The app answers each step before the next; a busy main thread makes the drive take longer.
    print("\(Int(speed)) pt/s over a \(Int(range)) pt transcript: \(seconds) s took \(String(format: "%.1f", took)) s")
case "sweep" where arguments.count == 3:
    let seconds = Double(arguments[2]) ?? 10
    let took = drive(seconds: seconds) { step, steps in
        let t = Double(step) / Double(steps)
        set(t < 0.5 ? 1 - t * 2 : (t - 0.5) * 2)
    }
    print("sweep: \(seconds) s took \(String(format: "%.1f", took)) s")
default:
    fail("unknown command \(arguments[1])")
}
