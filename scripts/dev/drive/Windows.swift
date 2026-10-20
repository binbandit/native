import ApplicationServices
import CoreGraphics
import Foundation

/// The instance's windows as the window server sees them, for listing and screenshots.
struct Windows {
    let pid: pid_t

    struct Window {
        let id: CGWindowID
        let layer: Int
        let title: String
        let bounds: CGRect
        let onScreen: Bool
    }

    /// Every window the process owns, front to back.
    func all() -> [Window] {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? Int == Int(pid),
                let id = info[kCGWindowNumber as String] as? Int
            else { return nil }
            return Window(
                id: CGWindowID(id), layer: info[kCGWindowLayer as String] as? Int ?? 0,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: Self.bounds(info), onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }

    /// The window to act on: the one asked for, which must be this instance's, else its frontmost
    /// normal window on screen.
    func pick(_ id: Int?) throws(DriveError) -> Window {
        let windows = all()
        if let id {
            guard let window = windows.first(where: { $0.id == CGWindowID(id) }) else {
                throw DriveError("window \(id) isn't one of this instance's; `windows` lists them")
            }
            return window
        }
        guard let window = windows.first(where: { $0.onScreen && $0.layer == 0 && $0.bounds.width > 100 }) else {
            throw DriveError("no window on screen; is it minimized or hidden?")
        }
        return window
    }

    /// The other apps' windows above `window` that overlap it. A covered window isn't redrawn, so
    /// a screenshot shows what it drew before it was covered.
    func covering(_ window: Window) -> [String] {
        let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], window.id) as? [[String: Any]] ?? []
        let owners = above.compactMap { info -> String? in
            guard info[kCGWindowOwnerPID as String] as? Int != Int(pid),
                (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                (info[kCGWindowLayer as String] as? Int ?? 0) < 20,
                Self.bounds(info).intersects(window.bounds)
            else { return nil }
            return info[kCGWindowOwnerName as String] as? String ?? "another app"
        }
        return Array(Set(owners)).sorted()
    }

    /// Captures one window, without its shadow and without a sound, with `screencapture -l`.
    func capture(_ window: Window, to path: String) throws(DriveError) {
        let task = Process()
        task.executableURL = URL(filePath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(window.id), path]
        do {
            try task.run()
        } catch {
            throw DriveError("couldn't run screencapture: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath: path) else {
            throw DriveError(
                "screencapture failed (status \(task.terminationStatus)); does this shell have Screen Recording?")
        }
    }

    func describe(_ window: Window) -> String {
        let bounds = window.bounds
        var parts = [
            "\(window.id)", "layer \(window.layer)",
            "\(Int(bounds.width))x\(Int(bounds.height)) at \(Int(bounds.minX)),\(Int(bounds.minY))",
            window.onScreen ? "on screen" : "off screen",
        ]
        if !window.title.isEmpty { parts.insert(Node.quoted(window.title), at: 1) }
        if window.onScreen {
            let covering = covering(window)
            if !covering.isEmpty { parts.append("covered by " + covering.joined(separator: ", ")) }
        }
        return parts.joined(separator: "  ")
    }

    /// Moves and resizes the main window through Accessibility, which doesn't bring it forward.
    /// `x` and `y` are its top left corner in screen points, from the top left of the main display.
    static func setFrame(of app: AXUIElement, to frame: CGRect) throws(DriveError) {
        let windows = Accessibility.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard
            let window = windows.first(where: {
                Accessibility.attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
            })
        else { throw DriveError("no window to move") }
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size),
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success,
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent) == .success
        else { throw DriveError("the window didn't take the frame") }
    }

    private static func bounds(_ info: [String: Any]) -> CGRect {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        else { return .zero }
        return rect
    }
}
