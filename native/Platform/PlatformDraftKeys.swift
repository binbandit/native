import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Backspace as it reaches a text editor, before the editor applies it.
struct DraftBackspaceKey {
    var isTextEmpty: Bool
    /// An input method is composing text (marked text), which Backspace edits.
    var isComposing: Bool
    var isRepeat: Bool
}

extension View {
    /// While `isEnabled`, hands Backspace in the text editor inside this view to `perform` before the
    /// editor applies it; the key goes no further when `perform` returns true. Apply it to the
    /// editor. The Mac's text view handles Delete itself (`deleteBackward:`), so SwiftUI's key
    /// handlers never hear it; iPadOS delivers it to `onKeyPress`, so this does nothing there.
    func onDraftBackspace(isEnabled: Bool, perform: @escaping (DraftBackspaceKey) -> Bool) -> some View {
        #if canImport(AppKit)
        background(DraftBackspaceMonitor(isEnabled: isEnabled, perform: perform))
        #else
        self
        #endif
    }

    /// Delete or Forward Delete while this view has keyboard focus: the Mac's Delete command, or the
    /// keys themselves on iPadOS.
    func onDeleteKey(perform: @escaping () -> Void) -> some View {
        #if os(macOS)
        onDeleteCommand(perform: perform)
        #else
        onKeyPress(keys: [.delete, .deleteForward]) { _ in
            perform()
            return .handled
        }
        #endif
    }
}

#if canImport(AppKit)
/// Watches this window's key events for Backspace while the editor beside it is first responder.
private struct DraftBackspaceMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let perform: (DraftBackspaceKey) -> Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.perform = perform
        context.coordinator.update(isEnabled: isEnabled, near: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.update(isEnabled: false, near: view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(perform: perform)
    }

    final class Coordinator {
        var perform: (DraftBackspaceKey) -> Bool
        private var monitor: Any?

        /// Backspace's virtual key code (`kVK_Delete`); Forward Delete is another key.
        private static let backspaceKeyCode: UInt16 = 51

        init(perform: @escaping (DraftBackspaceKey) -> Bool) {
            self.perform = perform
        }

        func update(isEnabled: Bool, near anchor: NSView) {
            if isEnabled, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak anchor] event in
                    guard let self, let anchor, event.keyCode == Self.backspaceKeyCode,
                        event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                        let window = anchor.window, event.window === window,
                        let textView = window.firstResponder as? NSTextView, !textView.isFieldEditor,
                        Self.isEditor(textView, under: anchor)
                    else { return event }
                    let key = DraftBackspaceKey(
                        isTextEmpty: textView.string.isEmpty, isComposing: textView.hasMarkedText(),
                        isRepeat: event.isARepeat)
                    return perform(key) ? nil : event
                }
            } else if !isEnabled, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        /// Whether `textView` is the editor this view sits behind, rather than another text view in
        /// the window (a question's answer field), which keeps its own Backspace.
        private static func isEditor(_ textView: NSTextView, under anchor: NSView) -> Bool {
            let editor = textView.enclosingScrollView ?? textView
            let frame = editor.convert(editor.bounds, to: nil)
            return anchor.convert(anchor.bounds, to: nil).contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}
#endif
