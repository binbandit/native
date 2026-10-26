import SwiftUI

#if os(macOS)
import AppKit
#endif

/// NSPopover's system chrome overrides the specified card shape. A nonactivating child panel
/// keeps this small menu opaque and anchored without changing the active application.
struct PlatformFolderRecentsPopover<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
    let attachmentAnchor: PopoverAttachmentAnchor
    @ViewBuilder let popup: () -> Popup
    @Environment(\.self) private var environment

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.background {
            SidebarFolderRecentsAnchor(
                isPresented: $isPresented,
                popup: AnyView(popup().environment(\.self, environment))
            )
            .allowsHitTesting(false)
        }
        #else
        content.popover(isPresented: $isPresented, attachmentAnchor: attachmentAnchor, arrowEdge: .top) {
            popup().presentationBackground(.clear).presentationCornerRadius(DS.Radius.card)
        }
        #endif
    }
}

#if os(macOS)
private struct SidebarFolderRecentsAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let popup: AnyView

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: NSView, context: Context) {
        if isPresented {
            context.coordinator.show(from: view, popup: popup) { isPresented = false }
        } else {
            context.coordinator.hide(notify: false, restoreFocus: true)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.hide(notify: false) }

    final class Coordinator {
        private var panel: SidebarFolderRecentsPanel?
        private var hosting: NSHostingView<AnyView>?
        private weak var parent: NSWindow?
        private weak var previousResponder: NSResponder?
        private var dismiss: (() -> Void)?
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []

        func show(from anchor: NSView, popup: AnyView, dismiss: @escaping () -> Void) {
            guard let parent = anchor.window else { return }
            self.dismiss = dismiss
            if let hosting, let panel {
                hosting.rootView = popup
                position(panel, hosting: hosting, anchor: anchor, parent: parent)
                return
            }
            self.parent = parent
            previousResponder = parent.firstResponder
            let hosting = NSHostingView(rootView: popup)
            hosting.sizingOptions = [.intrinsicContentSize]
            let panel = SidebarFolderRecentsPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.appearance = parent.effectiveAppearance
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
            position(panel, hosting: hosting, anchor: anchor, parent: parent)
            parent.addChildWindow(panel, ordered: .above)
            panel.order(.above, relativeTo: parent.windowNumber)
            // Opening an inactive fixture must not take the person's keyboard or raise its app.
            if NSApp.isActive && parent.isKeyWindow { panel.makeKey() }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                MainActor.assumeIsolated {
                    if let panel = self?.panel, event.window !== panel { self?.hide() }
                }
                return event
            }
            for (name, object) in [
                (NSApplication.didResignActiveNotification, nil),
                (NSWindow.willCloseNotification, parent),
                (NSWindow.didResignKeyNotification, panel),
            ] as [(Notification.Name, Any?)] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.hide() }
                    })
            }
        }

        private func position(_ panel: NSPanel, hosting: NSHostingView<AnyView>, anchor: NSView, parent: NSWindow) {
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            let source = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            var origin = NSPoint(x: source.minX + DS.Space.xxs, y: source.maxY + DS.Space.md)
            if let screen = parent.screen {
                origin.x = max(
                    screen.visibleFrame.minX + DS.Space.md,
                    min(origin.x, screen.visibleFrame.maxX - size.width - DS.Space.md))
                origin.y = min(origin.y, screen.visibleFrame.maxY - size.height - DS.Space.md)
            }
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        func hide(notify: Bool = true, restoreFocus: Bool = false) {
            guard let panel else { return }
            self.panel = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            parent?.removeChildWindow(panel)
            panel.close()
            hosting = nil
            if restoreFocus, NSApp.isActive, let parent, parent.isVisible, parent.attachedSheet == nil {
                parent.makeKey()
                if let previousResponder { parent.makeFirstResponder(previousResponder) }
            }
            let action = dismiss
            dismiss = nil
            if notify { action?() }
        }
    }
}

private final class SidebarFolderRecentsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
