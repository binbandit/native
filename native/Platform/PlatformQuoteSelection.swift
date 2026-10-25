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

    static func capture(task: UUID, source: ComposerQuoteSource? = nil) -> [PromptQuote]? {
        #if canImport(AppKit)
        guard
            let window = NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
        else { return nil }
        let text: String?
        let selectedText: String
        let range: NSRange
        let frame: CGRect
        if source == nil, let view = window.firstResponder as? NSTextView, view.selectedRange().length > 0 {
            text = view.string
            range = view.selectedRange()
            selectedText = (view.string as NSString).substring(with: range)
            frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        } else if let focused = selectedElement(in: window, task: task, source: source),
            let selected = focused.accessibilitySelectedText?() ?? nil, !selected.isEmpty
        {
            let readValue: (() -> Any?)? = focused.accessibilityValue
            let value = readValue?()
            text = (value as? String) ?? (value as? NSAttributedString)?.string
            selectedText = selected
            range = focused.accessibilitySelectedTextRange?() ?? NSRange(location: NSNotFound, length: 0)
            frame = focused.accessibilityFrame?() ?? .zero
        } else {
            return nil
        }
        let matching = entries.values.filter { entry in
            guard entry.task == task, source == nil || entry.source == source,
                let view = entry.view, view.window === window
            else { return false }
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
            guard entry.task == task, source == nil || entry.source == source,
                let anchor = entry.view, anchor.window === window
            else { return false }
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

    #if canImport(AppKit)
    private static func selectedElement(
        in window: NSWindow, task: UUID, source: ComposerQuoteSource?
    ) -> AnyObject? {
        guard let source else { return window.accessibilityFocusedUIElement as AnyObject? }
        let frames = entries.values.compactMap { entry -> CGRect? in
            guard entry.task == task, entry.source == source, let view = entry.view, view.window === window else {
                return nil
            }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        // A context menu can take focus away from selected SwiftUI text. Read only selected text
        // inside the source that opened it, through this window's own accessibility hierarchy.
        // SwiftUI nodes implement these public selectors without necessarily declaring the full
        // NSAccessibility protocol. Optional dispatch also traverses those nodes.
        func selected(in element: AnyObject, depth: Int) -> AnyObject? {
            guard depth < 64 else { return nil }
            if let frame = element.accessibilityFrame?(),
                frames.contains(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }),
                let text = element.accessibilitySelectedText?() ?? nil, !text.isEmpty
            {
                return element
            }
            for child in element.accessibilityChildren?() ?? [] {
                if let match = selected(in: child as AnyObject, depth: depth + 1) { return match }
            }
            return nil
        }
        return selected(in: window, depth: 0)
    }
    #endif

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
