import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

extension View {
    /// While `enabled`, Escape and ⌘. anywhere in this view's window run `cancel` and reach nothing
    /// else: not the composer's Stop, not a terminal, not the menu bar's ⌘. command. For a mode that
    /// owns the window for a moment, such as Try On Themes.
    ///
    /// On the Mac a key monitor takes the keys before the window or the menus see them. On iPad the
    /// mode's own shortcuts handle them (a focused view's `onKeyPress` and a `keyboardShortcut`):
    /// views inside read `windowClaimsCancelKeys` and leave Escape alone, and commands that use the
    /// same keys step aside while it runs.
    func windowCancelKeys(enabled: Bool, cancel: @escaping () -> Void) -> some View {
        #if canImport(AppKit)
        environment(\.windowClaimsCancelKeys, enabled)
            .background(WindowCancelKeyMonitor(enabled: enabled, cancel: cancel))
        #else
        environment(\.windowClaimsCancelKeys, enabled)
        #endif
    }
}

extension EnvironmentValues {
    /// Whether a mode owns Escape and ⌘. in this window (`windowCancelKeys`), so views that
    /// otherwise act on them, such as the composer's Stop, leave them alone.
    @Entry var windowClaimsCancelKeys = false
}

#if canImport(AppKit)
private struct WindowCancelKeyMonitor: NSViewRepresentable {
    let enabled: Bool
    let cancel: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.cancel = cancel
        context.coordinator.update(view: view, enabled: enabled)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        var cancel: (() -> Void)?
        private var monitor: Any?

        func update(view: NSView, enabled: Bool) {
            guard enabled else { stop(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let window = view?.window, event.window === window, Self.cancels(event, in: window)
                    else { return false }
                    self.cancel?()
                    return true
                }
                return consumed ? nil : event
            }
        }

        /// Escape or ⌘. with no other modifier, unless it finishes text the user is composing
        /// (an input method's marked text), which Escape abandons.
        private static func cancels(_ event: NSEvent, in window: NSWindow) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let isEscape = event.keyCode == 53 && modifiers.isEmpty
            let isCommandPeriod = event.charactersIgnoringModifiers == "." && modifiers == .command
            guard isEscape || isCommandPeriod else { return false }
            return (window.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
