import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Hosts SwiftUI action rows in a native pull-down, including its full menu-tracking lifetime.
struct PlatformProjectActionsMenuTrigger<Content: View>: View {
    let projectName: String
    var isSingle = false
    @Binding var isHovered: Bool
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if canImport(AppKit)
        ProjectActionsMenuRepresentable(
            projectName: projectName, isSingle: isSingle, isHovered: $isHovered, isOpen: $isOpen, content: content)
        #else
        Menu(content: content) {
            Color.clear.contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Project Actions")
        .accessibilityValue(projectName)
        #endif
    }
}

#if canImport(AppKit)
private struct ProjectActionsMenuRepresentable<Content: View>: NSViewRepresentable {
    let projectName: String
    let isSingle: Bool
    @Binding var isHovered: Bool
    @Binding var isOpen: Bool
    let content: () -> Content

    func makeNSView(context: Context) -> ProjectActionsMenuTriggerView {
        ProjectActionsMenuTriggerView()
    }

    func updateNSView(_ view: ProjectActionsMenuTriggerView, context: Context) {
        let environment = context.environment
        view.makeMenu = { NSHostingMenu(rootView: content().environment(\.self, environment)) }
        view.isSingle = isSingle
        view.onHoverChange = { hovering in
            withAnimation(hovering ? nil : .dsHoverOut) { isHovered = hovering }
        }
        view.onOpenChange = { isOpen = $0 }
        view.toolTip = "Actions for \(projectName)"
        view.setAccessibilityLabel("Project Actions")
        view.setAccessibilityValue(projectName)
    }
}

private final class ProjectActionsMenuTriggerView: NSView {
    var makeMenu: () -> NSMenu = { NSMenu() }
    var isSingle = false
    var onHoverChange: (Bool) -> Void = { _ in }
    var onOpenChange: (Bool) -> Void = { _ in }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange(false) }
    override func mouseDown(with event: NSEvent) { showMenu() }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || [.downArrow, .carriageReturn, .enter].contains(event.specialKey)
        {
            showMenu()
        } else {
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isSingle ? DS.Radius.control : 0,
            bottomLeadingRadius: isSingle ? DS.Radius.control : 0,
            bottomTrailingRadius: DS.Radius.control, topTrailingRadius: DS.Radius.control)
        NSBezierPath(cgPath: shape.path(in: bounds).cgPath).fill()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }
    override func accessibilityPerformPress() -> Bool {
        showMenu()
        return true
    }

    private func showMenu() {
        let menu = makeMenu()
        onOpenChange(true)
        let location = NSPoint(
            x: bounds.maxX - menu.size.width,
            y: isFlipped ? bounds.maxY + DS.RunControl.menuOffset : bounds.minY - DS.RunControl.menuOffset)
        menu.popUp(positioning: nil, at: location, in: self)
        onOpenChange(false)
        // Menus consume pointer events, so reconcile hover after tracking ends.
        if let window {
            onHoverChange(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
        }
    }
}
#endif

#if DEBUG
#Preview("Run - Native menu trigger") { ProjectActionsRunPreview(interaction: .menuOpen) }
#endif
