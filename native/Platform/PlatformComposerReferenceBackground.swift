import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// TextEditor only offers square character backgrounds. Draw the shared file chip behind the
/// editor using its actual text layout, so wrapping, selection and scrolling stay native.
struct PlatformComposerReferenceBackground: View {
    let ranges: [NSRange]

    var body: some View {
        ReferenceBackground(ranges: ranges).allowsHitTesting(false).accessibilityHidden(true)
    }
}

#if canImport(AppKit)
private struct ReferenceBackground: NSViewRepresentable {
    let ranges: [NSRange]

    func makeNSView(context: Context) -> ReferenceBackgroundView { ReferenceBackgroundView() }
    func updateNSView(_ view: ReferenceBackgroundView, context: Context) {
        view.ranges = ranges
        view.invalidate()
    }
}

private final class ReferenceBackgroundView: NSView {
    var ranges: [NSRange] = []
    private weak var editor: NSTextView?
    private var scrolling: NSObjectProtocol?
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidate()
    }

    func invalidate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var ancestor = superview
            for _ in 0..<4 {
                guard let view = ancestor else { break }
                if let text = Self.findEditor(in: view, depth: 6) {
                    if editor !== text {
                        if let scrolling { NotificationCenter.default.removeObserver(scrolling) }
                        editor = text
                        scrolling = NotificationCenter.default.addObserver(
                            forName: NSView.boundsDidChangeNotification,
                            object: text.enclosingScrollView?.contentView, queue: .main
                        ) { [weak self] _ in
                            MainActor.assumeIsolated { self?.needsDisplay = true }
                        }
                    }
                    break
                }
                ancestor = view.superview
            }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let editor, let layout = editor.textLayoutManager,
            let content = layout.textContentManager
        else { return }
        NSColor(Color.dsFill).setFill()
        for range in ranges {
            guard NSMaxRange(range) <= editor.string.utf16.count,
                let start = content.location(content.documentRange.location, offsetBy: range.location),
                let end = content.location(start, offsetBy: range.length),
                let textRange = NSTextRange(location: start, end: end)
            else { continue }
            layout.enumerateTextSegments(
                in: textRange, type: .standard, options: .rangeNotRequired
            ) { _, rect, _, _ in
                var rect = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                rect = self.convert(rect, from: editor).insetBy(dx: 0, dy: -DS.ComposerReference.verticalInset)
                NSBezierPath(roundedRect: rect, xRadius: DS.Radius.control, yRadius: DS.Radius.control).fill()
                return true
            }
        }
    }

    private static func findEditor(in view: NSView, depth: Int) -> NSTextView? {
        if let text = view as? NSTextView, !text.isFieldEditor { return text }
        guard depth > 0 else { return nil }
        return view.subviews.lazy.compactMap { findEditor(in: $0, depth: depth - 1) }.first
    }

    isolated deinit {
        if let scrolling { NotificationCenter.default.removeObserver(scrolling) }
    }
}
#else
private struct ReferenceBackground: UIViewRepresentable {
    let ranges: [NSRange]
    func makeUIView(context: Context) -> ReferenceBackgroundView {
        let view = ReferenceBackgroundView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: ReferenceBackgroundView, context: Context) {
        view.ranges = ranges
        view.setNeedsDisplay()
    }
}

private final class ReferenceBackgroundView: UIView {
    var ranges: [NSRange] = []

    override func draw(_ rect: CGRect) {
        var ancestor = superview
        var editor: UITextView?
        for _ in 0..<4 {
            guard let view = ancestor else { break }
            editor = Self.findEditor(in: view, depth: 6)
            if editor != nil { break }
            ancestor = view.superview
        }
        guard let editor else { return }
        UIColor(Color.dsFill).setFill()
        for range in ranges {
            guard let start = editor.position(from: editor.beginningOfDocument, offset: range.location),
                let end = editor.position(from: start, offset: range.length),
                let textRange = editor.textRange(from: start, to: end)
            else { continue }
            for segment in editor.selectionRects(for: textRange) {
                let rect = convert(segment.rect, from: editor).insetBy(dx: 0, dy: -DS.ComposerReference.verticalInset)
                UIBezierPath(roundedRect: rect, cornerRadius: DS.Radius.control).fill()
            }
        }
    }

    private static func findEditor(in view: UIView, depth: Int) -> UITextView? {
        if let text = view as? UITextView { return text }
        guard depth > 0 else { return nil }
        return view.subviews.lazy.compactMap { findEditor(in: $0, depth: depth - 1) }.first
    }
}
#endif
