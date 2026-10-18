import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

extension View {
    /// Lets the text view in this view take only dragged text, so files and images dropped on it
    /// fall through to the drop destination around it instead of landing in the text as paths or
    /// stray attachments. Apply it to a `TextEditor`. The Mac's text view registers for every type
    /// it can draw; iPadOS needs nothing.
    func textViewTakesOnlyTextDrops() -> some View {
        #if canImport(AppKit)
        background(TextOnlyDrops())
        #else
        self
        #endif
    }
}

#if canImport(AppKit)
/// Finds the editor's text view beside it and narrows what it registers for. The text view
/// registers again when it's enabled or disabled, so this runs on every update.
private struct TextOnlyDrops: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Anchor()
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? Anchor)?.narrow()
    }

    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            narrow()
        }

        /// The nearest text view among the anchor's relatives: the editor it's the background of.
        func narrow() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                for _ in 0..<4 {
                    guard let view = ancestor else { return }
                    if let textView = Self.textView(in: view, depth: 6) {
                        let text: [NSPasteboard.PasteboardType] = [.string]
                        if textView.registeredDraggedTypes != text {
                            textView.unregisterDraggedTypes()
                            textView.registerForDraggedTypes(text)
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }

        private static func textView(in view: NSView, depth: Int) -> NSTextView? {
            if let textView = view as? NSTextView, !textView.isFieldEditor { return textView }
            guard depth > 0 else { return nil }
            return view.subviews.lazy.compactMap { textView(in: $0, depth: depth - 1) }.first
        }
    }
}
#endif
