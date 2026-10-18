import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Code shown by the platform's own text view (NSTextView on the Mac, UITextView on iPad): TextKit
/// lays it out and draws it off SwiftUI's text path, which keeps long lists of code smooth, and it
/// keeps real selection. Every line is exactly `lineHeight` tall (see `attributed(_:font:lineHeight:in:)`),
/// so the view's size is known without laying anything out, and views beside it can line up rows.
///
/// Not editable. Links in the text (`.link`) go to `onLink` instead of a browser. Right-clicks pass
/// through to SwiftUI, so a `.contextMenu` around the view still shows.
struct PlatformCodeText: View, Equatable {
    let text: NSAttributedString
    /// Identifies `text`: the view only reloads when this changes.
    let key: String
    let lineCount: Int
    let lineHeight: CGFloat
    var isSelectable = true
    var onLink: ((URL) -> Void)?

    var body: some View {
        PlatformCodeTextRepresentable(
            text: text, key: key, lineCount: lineCount, lineHeight: lineHeight, isSelectable: isSelectable,
            onLink: onLink)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.lineCount == rhs.lineCount && lhs.lineHeight == rhs.lineHeight
            && lhs.isSelectable == rhs.isSelectable
    }

    /// The height every line takes in `font` with `spacing` between lines, as SwiftUI's
    /// `.lineSpacing` would set it.
    static func lineHeight(font: DSPlatformFont, spacing: CGFloat) -> CGFloat {
        #if canImport(AppKit)
        NSLayoutManager().defaultLineHeight(for: font) + spacing
        #else
        font.lineHeight + spacing
        #endif
    }

    /// `text` ready for a code text view: SwiftUI colors resolved for `environment`, set in `font`,
    /// and every line exactly `lineHeight` tall with its glyphs centered in it.
    static func attributed(
        _ text: AttributedString, font: DSPlatformFont, lineHeight: CGFloat, in environment: EnvironmentValues
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping
        // TextKit puts a tall line's extra height above the glyphs; half of it goes back under.
        let natural = Self.lineHeight(font: font, spacing: 0)
        let base: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph, .baselineOffset: max(0, lineHeight - natural) / 2,
        ]
        let result = NSMutableAttributedString(string: String(text.characters), attributes: base)
        // Runs share a handful of colors; resolving each once keeps building a block cheap.
        var resolved: [Color: DSPlatformColor] = [:]
        func platform(_ color: Color) -> DSPlatformColor {
            if let known = resolved[color] { return known }
            let cgColor = color.resolve(in: environment).cgColor
            #if canImport(AppKit)
            let value = NSColor(cgColor: cgColor) ?? .labelColor
            #else
            let value = UIColor(cgColor: cgColor)
            #endif
            resolved[color] = value
            return value
        }
        for run in text.runs {
            let range = NSRange(run.range, in: text)
            if let color = run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] {
                result.addAttribute(.foregroundColor, value: platform(color), range: range)
            }
            if let color = run[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] {
                result.addAttribute(.backgroundColor, value: platform(color), range: range)
            }
            if let link = run[AttributeScopes.FoundationAttributes.LinkAttribute.self] {
                result.addAttribute(.link, value: link, range: range)
            }
        }
        return result
    }
}

#if canImport(AppKit)
private struct PlatformCodeTextRepresentable: NSViewRepresentable {
    let text: NSAttributedString
    let key: String
    let lineCount: Int
    let lineHeight: CGFloat
    let isSelectable: Bool
    let onLink: ((URL) -> Void)?

    func makeCoordinator() -> PlatformCodeTextLinks { PlatformCodeTextLinks() }

    func makeNSView(context: Context) -> PlatformCodeNSTextView {
        let view = PlatformCodeNSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = isSelectable
        view.passesClicks = !isSelectable
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.clipsToBounds = true
        // Links keep the text's own look; only the cursor says they're clickable.
        view.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PlatformCodeNSTextView, context: Context) {
        context.coordinator.onLink = onLink
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        view.textStorage?.setAttributedString(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlatformCodeNSTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: CGFloat(lineCount) * lineHeight)
    }
}

/// Code's text view. Right-clicks go on to SwiftUI for its context menu, and a view that isn't
/// selectable lets clicks through to the gestures around it.
private final class PlatformCodeNSTextView: NSTextView {
    var passesClicks = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesClicks ? nil : super.hitTest(point)
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
}

private final class PlatformCodeTextLinks: NSObject, NSTextViewDelegate {
    var key: String?
    var onLink: ((URL) -> Void)?

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, let onLink else { return false }
        onLink(url)
        return true
    }
}
#else
private struct PlatformCodeTextRepresentable: UIViewRepresentable {
    let text: NSAttributedString
    let key: String
    let lineCount: Int
    let lineHeight: CGFloat
    let isSelectable: Bool
    let onLink: ((URL) -> Void)?

    func makeCoordinator() -> PlatformCodeTextLinks { PlatformCodeTextLinks() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = isSelectable
        view.isUserInteractionEnabled = isSelectable
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = false
        view.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.clipsToBounds = true
        view.linkTextAttributes = [:]
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onLink = onLink
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        view.attributedText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: CGFloat(lineCount) * lineHeight)
    }
}

private final class PlatformCodeTextLinks: NSObject, UITextViewDelegate {
    var key: String?
    var onLink: ((URL) -> Void)?

    func textView(
        _ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction
    ) -> UIAction? {
        guard case .link(let url) = textItem.content, let onLink else { return defaultAction }
        return UIAction { _ in onLink(url) }
    }
}
#endif
