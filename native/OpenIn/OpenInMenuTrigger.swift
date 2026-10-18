import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// The chevron half of the Open In control: the hit area that opens the app menu, with the glyph
/// and hover fill drawn around it by `OpenInButton`. On the Mac it's AppKit underneath, so the menu
/// behaves like a native pull-down: it opens on mouse-down (press, drag to an app, release), from
/// the keyboard (Space, Return or ↓ with Full Keyboard Access) and from VoiceOver, and it's
/// right-aligned under the control. Elsewhere it's a SwiftUI menu.
struct OpenInMenuTrigger: View {
    let location: OpenInLocation
    let model: OpenInModel
    @Binding var isHovered: Bool
    @Binding var isOpen: Bool

    private static let label = "Open In…"

    var body: some View {
        #if canImport(AppKit)
        OpenInMenuTriggerRepresentable(label: Self.label, isHovered: $isHovered, isOpen: $isOpen) {
            OpenInMenu.make(for: location, model: model)
        }
        #else
        Menu {
            OpenInMenuContent(location: location, model: model)
        } label: {
            Color.clear.contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Self.label)
        #endif
    }
}

#if canImport(AppKit)
private struct OpenInMenuTriggerRepresentable: NSViewRepresentable {
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

    /// How far the menu's top edge sits below the control: a 4pt gap, plus
    /// the padding NSMenu draws above the item placed at the pop-up location (5pt on macOS 27).
    private static let menuOffset = DS.Space.xs + 5

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
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
        let isSpace = event.charactersIgnoringModifiers == " "
        if isSpace || [.downArrow, .carriageReturn, .enter].contains(event.specialKey) {
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
            y: isFlipped ? bounds.maxY + Self.menuOffset : bounds.minY - Self.menuOffset
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
#endif
