import AppKit
import SwiftUI

/// The chevron half of the Open In control. It's AppKit underneath so the menu behaves like a
/// native pull-down: it opens on mouse-down (press, drag to an app, release), from the keyboard
/// (Space, Return or ↓ with Full Keyboard Access) and from VoiceOver, and it's right-aligned under
/// the control as the reference app's is. The glyph and hover fill are drawn by SwiftUI around it.
struct OpenInMenuTrigger: NSViewRepresentable {
    let label: String
    @Binding var isHovered: Bool
    @Binding var isOpen: Bool
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> OpenInMenuTriggerView {
        OpenInMenuTriggerView()
    }

    func updateNSView(_ view: OpenInMenuTriggerView, context: Context) {
        view.makeMenu = makeMenu
        view.onHoverChange = { isHovered = $0 }
        view.onOpenChange = { isOpen = $0 }
        view.toolTip = label
        view.setAccessibilityLabel(label)
    }
}

final class OpenInMenuTriggerView: NSView {
    var makeMenu: () -> NSMenu = { NSMenu() }
    var onHoverChange: (Bool) -> Void = { _ in }
    var onOpenChange: (Bool) -> Void = { _ in }

    /// Matches the gap the reference app leaves between a trigger and its popover (`sideOffset` 4px).
    private static let menuGap = DS.Space.xs

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }

    override func mouseDown(with event: NSEvent) {
        showMenu()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }

    override func keyDown(with event: NSEvent) {
        let opensMenu = [.downArrow, .carriageReturn, .enter].contains(event.specialKey) || event.charactersIgnoringModifiers == " "
        if opensMenu {
            showMenu()
        } else {
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: DS.Radius.control, yRadius: DS.Radius.control).fill()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }

    override func accessibilityPerformPress() -> Bool {
        showMenu()
        return true
    }

    /// Pops the menu right-aligned under the control. This returns once the menu closes.
    private func showMenu() {
        let menu = makeMenu()
        onOpenChange(true)
        let location = NSPoint(
            x: bounds.maxX - menu.size.width,
            y: isFlipped ? bounds.maxY + Self.menuGap : bounds.minY - Self.menuGap
        )
        menu.popUp(positioning: nil, at: location, in: self)
        onOpenChange(false)
        // The pointer may have left while the menu was up, which sends no exit event.
        if let window {
            let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            onHoverChange(bounds.contains(pointer))
        }
    }
}
