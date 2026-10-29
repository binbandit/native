import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension View {
    /// SwiftUI owns the editor's drops. Registering even plain text here steals files that also
    /// advertise a string, inserting their paths before the attachment destination sees them.
    func textViewDefersDrops() -> some View {
        background(TextOnlyDrops())
    }
}

#if canImport(AppKit)
/// Finds the editor's text view beside it and removes its native drop registration. The text view
/// registers again when it's enabled or disabled, so this runs on every update.
private struct TextOnlyDrops: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Anchor()
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? Anchor)?.narrow()
    }

    final class Anchor: NSView {
        #if DEBUG
        private var dropCheck: PlatformAttachmentDropCheck?
        #endif

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            #if DEBUG
            dropCheck = window == nil ? nil : PlatformAttachmentDropCheck(anchor: self)
            #endif
            narrow()
        }

        /// The nearest text view among the anchor's relatives: the editor it's the background of.
        func narrow() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                for _ in 0..<4 {
                    guard let view = ancestor else { return }
                    if let textView = Self.textView(in: view, depth: 6) {
                        if !textView.registeredDraggedTypes.isEmpty {
                            textView.unregisterDraggedTypes()
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
#else
private struct TextOnlyDrops: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Anchor() }
    func updateUIView(_ view: UIView, context: Context) { (view as? Anchor)?.deferDrops() }

    final class Anchor: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            deferDrops()
        }

        func deferDrops() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                for _ in 0..<4 {
                    guard let view = ancestor else { return }
                    if let text = Self.textView(in: view, depth: 6) {
                        if let interaction = text.textDropInteraction,
                            text.interactions.contains(where: { $0 === interaction })
                        {
                            text.removeInteraction(interaction)
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }

        private static func textView(in view: UIView, depth: Int) -> UITextView? {
            if let text = view as? UITextView { return text }
            guard depth > 0 else { return nil }
            return view.subviews.lazy.compactMap { textView(in: $0, depth: depth - 1) }.first
        }
    }
}
#endif
