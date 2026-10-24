import ACP
import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Source anchors belong only to Native's current views. Selection never reads the pasteboard or
/// another application, and no selection from an editor or settings field has an eligible anchor.
@MainActor
enum PlatformQuoteSelection {
    final class Entry {
        weak var view: DSPlatformView?
        var task: UUID
        var source: ComposerQuoteSource

        init(view: DSPlatformView, task: UUID, source: ComposerQuoteSource) {
            self.view = view
            self.task = task
            self.source = source
        }
    }

    static var entries: [UUID: Entry] = [:]

    static func capture(task: UUID) -> [PromptQuote]? {
        #if canImport(AppKit)
        guard
            let window = NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
        else { return nil }
        let text: String?
        let selectedText: String
        let range: NSRange
        let frame: CGRect
        if let view = window.firstResponder as? NSTextView, view.selectedRange().length > 0 {
            text = view.string
            range = view.selectedRange()
            selectedText = (view.string as NSString).substring(with: range)
            frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        } else if let focused = window.accessibilityFocusedUIElement as? any NSAccessibilityProtocol,
            let selected = focused.accessibilitySelectedText(), !selected.isEmpty
        {
            text =
                (focused.accessibilityValue() as? String)
                ?? (focused.accessibilityValue() as? NSAttributedString)?.string
            selectedText = selected
            range = focused.accessibilitySelectedTextRange()
            frame = focused.accessibilityFrame()
        } else {
            return nil
        }
        let matching = entries.values.filter { entry in
            guard entry.task == task, let view = entry.view, view.window === window else { return false }
            return window.convertToScreen(view.convert(view.bounds, to: nil)).contains(
                CGPoint(x: frame.midX, y: frame.midY))
        }
        #else
        guard
            let view = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).filter(\.isKeyWindow).compactMap({ selectedView(in: $0) }).first,
            let window = view.window
        else { return nil }
        let text: String? = view.text
        let range = view.selectedRange
        let selectedText = ((view.text ?? "") as NSString).substring(with: range)
        let frame = view.convert(view.bounds, to: window)
        let matching = entries.values.filter { entry in
            guard entry.task == task, let anchor = entry.view, anchor.window === window else { return false }
            return anchor.convert(anchor.bounds, to: window).contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        #endif
        guard let entry = matching.min(by: { area($0) < area($1) }) else { return nil }
        if let text,
            let quote = PromptQuote(
                source: entry.source.name, text: text, selection: range,
                firstLine: entry.source.firstLine, side: entry.source.side)
        {
            return [quote]
        }
        // Some SwiftUI prose exposes the selected words but no full value. Only a unique match
        // can locate their line numbers without guessing between repeated source lines.
        guard let source = entry.source.text, let found = source.range(of: selectedText),
            source[found.upperBound...].range(of: selectedText) == nil,
            let quote = PromptQuote(
                source: entry.source.name, text: source, selection: NSRange(found, in: source),
                firstLine: entry.source.firstLine, side: entry.source.side)
        else { return nil }
        return [quote]
    }

    private static func area(_ entry: Entry) -> CGFloat {
        guard let size = entry.view?.bounds.size else { return .greatestFiniteMagnitude }
        return size.width * size.height
    }

    #if !canImport(AppKit)
    private static func selectedView(in view: UIView) -> UITextView? {
        if let text = view as? UITextView, text.isFirstResponder, text.selectedRange.length > 0 { return text }
        return view.subviews.compactMap { selectedView(in: $0) }.first
    }
    #endif
}

#if canImport(AppKit)
typealias DSPlatformView = NSView
struct PlatformQuoteSelectionAnchor: NSViewRepresentable {
    let task: UUID
    let source: ComposerQuoteSource
    func makeCoordinator() -> UUID { UUID() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        PlatformQuoteSelection.entries[context.coordinator] = .init(view: view, task: task, source: source)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        PlatformQuoteSelection.entries[context.coordinator]?.source = source
        PlatformQuoteSelection.entries[context.coordinator]?.task = task
    }
    static func dismantleNSView(_ view: NSView, coordinator: UUID) {
        PlatformQuoteSelection.entries[coordinator] = nil
    }
}
#else
typealias DSPlatformView = UIView
struct PlatformQuoteSelectionAnchor: UIViewRepresentable {
    let task: UUID
    let source: ComposerQuoteSource
    func makeCoordinator() -> UUID { UUID() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        PlatformQuoteSelection.entries[context.coordinator] = .init(view: view, task: task, source: source)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        PlatformQuoteSelection.entries[context.coordinator]?.source = source
        PlatformQuoteSelection.entries[context.coordinator]?.task = task
    }
    static func dismantleUIView(_ view: UIView, coordinator: UUID) {
        PlatformQuoteSelection.entries[coordinator] = nil
    }
}
#endif
