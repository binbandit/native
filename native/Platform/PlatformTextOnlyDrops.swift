import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension View {
    /// SwiftUI owns the editor's drops. Registering even plain text here steals files that also
    /// advertise a string, inserting their paths before the attachment destination sees them.
    func textViewDefersDrops(_ defersDrops: Bool) -> some View {
        background(TextOnlyDrops(defersDrops: defersDrops))
    }
}

#if canImport(AppKit)
/// Finds the editor's text view beside it and removes its native drop registration. The text view
/// registers again when it's enabled or disabled, so this runs on every update.
private struct TextOnlyDrops: NSViewRepresentable {
    let defersDrops: Bool
    func makeNSView(context: Context) -> NSView {
        Anchor()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let anchor = view as? Anchor else { return }
        anchor.defersDrops = defersDrops
        anchor.narrow()
    }

    final class Anchor: NSView {
        var defersDrops = false
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
                        let types: [NSPasteboard.PasteboardType] = self?.defersDrops == true ? [] : [.string]
                        if textView.registeredDraggedTypes != types {
                            textView.unregisterDraggedTypes()
                            textView.registerForDraggedTypes(types)
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
    let defersDrops: Bool
    func makeUIView(context: Context) -> UIView { Anchor() }
    func updateUIView(_ view: UIView, context: Context) {
        guard let anchor = view as? Anchor else { return }
        anchor.defersDrops = defersDrops
        anchor.deferDrops()
    }

    final class Anchor: UIView {
        var defersDrops = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            deferDrops()
        }

        func deferDrops() {
            DispatchQueue.main.async { [weak self] in
                guard self?.defersDrops == true else { return }
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
