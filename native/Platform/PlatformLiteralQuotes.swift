import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension View {
    /// File mentions use straight quotes as delimiters, including while completing a child path.
    func textInputKeepsLiteralQuotes() -> some View {
        background(PlatformLiteralQuotes())
    }
}

#if canImport(AppKit)
private struct PlatformLiteralQuotes: NSViewRepresentable {
    func makeNSView(context: Context) -> LiteralQuotesAnchor { LiteralQuotesAnchor() }
    func updateNSView(_ view: LiteralQuotesAnchor, context: Context) { view.configure() }
}

private final class LiteralQuotesAnchor: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    func configure() {
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            for _ in 0..<4 {
                guard let view = ancestor else { return }
                if let editor = Self.findEditor(in: view, depth: 6) {
                    editor.isAutomaticQuoteSubstitutionEnabled = false
                    return
                }
                ancestor = view.superview
            }
        }
    }

    private static func findEditor(in view: NSView, depth: Int) -> NSTextView? {
        if let editor = view as? NSTextView, !editor.isFieldEditor { return editor }
        guard depth > 0 else { return nil }
        return view.subviews.lazy.compactMap { findEditor(in: $0, depth: depth - 1) }.first
    }
}
#else
private struct PlatformLiteralQuotes: UIViewRepresentable {
    func makeUIView(context: Context) -> LiteralQuotesAnchor { LiteralQuotesAnchor() }
    func updateUIView(_ view: LiteralQuotesAnchor, context: Context) { view.configure() }
}

private final class LiteralQuotesAnchor: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        configure()
    }

    func configure() {
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            for _ in 0..<4 {
                guard let view = ancestor else { return }
                if let editor = Self.findEditor(in: view, depth: 6) {
                    editor.smartQuotesType = .no
                    return
                }
                ancestor = view.superview
            }
        }
    }

    private static func findEditor(in view: UIView, depth: Int) -> UITextView? {
        if let editor = view as? UITextView { return editor }
        guard depth > 0 else { return nil }
        return view.subviews.lazy.compactMap { findEditor(in: $0, depth: depth - 1) }.first
    }
}
#endif
