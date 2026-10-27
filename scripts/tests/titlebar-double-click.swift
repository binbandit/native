import AppKit
import SwiftUI

@main
@MainActor
private struct TitlebarDoubleClickChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL \(message)"); failures += 1 }
        }
        for state in TitlebarFixture.State.allCases {
            let fixture = TitlebarFixture(state: state)
            let window = fixture.window
            fixture.preference("Maximize")
            fixture.click(fixture.background)
            check(window.zooms == 1, "\(state): empty toolbar double-click did not zoom exactly once")
            #if !BEFORE
            for edge in 0...1 {
                let point =
                    edge == 0
                    ? NSPoint(x: 90, y: window.frame.height - 20)
                    : NSPoint(x: window.frame.width - 2, y: window.contentLayoutRect.maxY + 10)
                let zooms = window.zooms
                fixture.click(point)
                check(window.zooms == zooms + 1, "\(state): empty title bar or toolbar edge at \(point) did not zoom")
            }
            let original = window.frame
            fixture.click(fixture.background)
            fixture.click(fixture.background)
            check(window.frame == original, "\(state): a second zoom did not restore the frame")

            for preference in ["None", "unexpected"] {
                fixture.preference(preference)
                let zooms = window.zooms
                let frame = window.frame
                fixture.click(fixture.background)
                check(window.zooms == zooms && window.frame == frame, "\(state): \(preference) changed the window")
            }
            fixture.preference(nil)
            let zooms = window.zooms
            fixture.click(fixture.background)
            check(window.zooms == zooms + 1, "\(state): absent preference did not default to zoom")
            fixture.preference("Minimize")
            fixture.click(fixture.background)
            check(window.minimizations == 1, "\(state): Minimize did not minimize")

            fixture.preference("Fill")
            let beforeFill = window.frame
            fixture.click(fixture.background)
            check(window.frame == window.screen?.visibleFrame, "\(state): Fill did not fill the visible screen")
            fixture.click(fixture.background)
            check(window.frame == beforeFill, "\(state): Fill did not restore the previous frame")
            fixture.click(fixture.background)
            window.setFrame(beforeFill, display: false)
            fixture.click(fixture.background)
            fixture.click(fixture.background)
            check(window.frame == beforeFill, "\(state): manual resize left a stale Fill restore frame")

            fixture.preference("Maximize")
            let beforeControls = window.zooms
            for point in fixture.controls {
                fixture.click(point)
            }
            check(!fixture.controls.isEmpty, "\(state): no toolbar controls were tested")
            check(window.zooms == beforeControls, "\(state): a toolbar item or task title zoomed the window")
            fixture.click(NSPoint(x: 500, y: 100))
            fixture.click(fixture.background, count: 1)
            fixture.click(fixture.background, count: 3)
            fixture.click(fixture.background, modifiers: .control)
            check(window.zooms == beforeControls, "\(state): content, single/triple click or context click zoomed")

            let other = TitlebarCheckWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            fixture.click(NSPoint(x: 500, y: 490), window: other)
            check(other.zooms == 0, "\(state): the monitor handled another window")
            other.close()
            #endif
            fixture.close()
        }
        guard failures == 0 else { exit(1) }
        print("PASS titlebar double-click checks: ordinary, well, Settings; preferences, restore and exclusions")
    }
}

@MainActor
private final class TitlebarFixture {
    enum State: CaseIterable { case ordinary, well, settings }
    let window: TitlebarCheckWindow

    init(state: State) {
        let page = Text("Content")
            .navigationTitle(state == .settings ? "Settings" : "Task title")
            .toolbar {
                if state == .well {
                    ToolbarItem(placement: .navigation) { Text("Task title") }
                    ToolbarItem(placement: .principal) { Button("The well") {} }
                }
                ToolbarItem { Button("Control") {} }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        let content = NavigationSplitView {
            Text("Sidebar")
        } detail: {
            if state == .ordinary {
                page
            } else {
                page.toolbar(removing: .title)
            }
        }
        #if BEFORE
        let host = NSHostingController(rootView: content)
        #else
        let host = NSHostingController(rootView: content.platformTitlebarDoubleClick())
        #endif
        window = TitlebarCheckWindow(contentViewController: host)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.setFrame(NSRect(x: 100, y: 100, width: 1000, height: 700), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    var background: NSPoint { NSPoint(x: window.frame.width - 2, y: window.frame.height - 20) }

    var controls: [NSPoint] {
        var views = (window.toolbar?.items ?? []).compactMap { item -> NSView? in
            guard item.itemIdentifier != .space, item.itemIdentifier != .flexibleSpace else { return nil }
            return item.view
        }
        func collect(_ view: NSView) {
            if view is NSTextField { views.append(view) }
            for child in view.subviews { collect(child) }
        }
        if let root = window.contentView?.superview { collect(root) }
        return views.filter { !$0.isHidden && !$0.bounds.isEmpty }.map {
            $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil)
        }
    }

    func preference(_ value: String?) {
        UserDefaults.standard.setVolatileDomain(
            value.map { ["AppleActionOnDoubleClick": $0] } ?? [:], forName: UserDefaults.argumentDomain)
    }

    func click(_ point: NSPoint, count: Int = 2, modifiers: NSEvent.ModifierFlags = [], window: NSWindow? = nil) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: (window ?? self.window).windowNumber,
                    context: nil, eventNumber: 1, clickCount: count, pressure: 0)
            else { fatalError("Could not construct a test event") }
            NSApplication.shared.sendEvent(event)
        }
    }

    func close() { window.close() }
}

@MainActor
private final class TitlebarCheckWindow: NSWindow {
    var zooms = 0
    var minimizations = 0
    override func performZoom(_ sender: Any?) {
        zooms += 1
        super.performZoom(sender)
    }
    override func miniaturize(_ sender: Any?) { minimizations += 1 }
}
