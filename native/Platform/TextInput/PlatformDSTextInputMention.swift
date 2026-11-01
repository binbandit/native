import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A single TextKit character gives deletion, selection and undo their native atomic semantics.
nonisolated final class PlatformDSTextInputMention: NSTextAttachment {
    let path: String

    @MainActor init(path: String, style: PlatformDSTextInputStyle) {
        self.path = path
        super.init(data: nil, ofType: nil)
        let label = "@" + (path as NSString).lastPathComponent
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.font, .foregroundColor: style.foreground, .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = CGSize(
            width: min(DS.TextInput.tokenMaximumWidth, ceil(text.size().width) + DS.TextInput.tokenInset * 2),
            height: ceil(style.font.ascender - style.font.descender) + DS.TextInput.tokenInset)
        #if canImport(AppKit)
        image = NSImage(size: size, flipped: false) { rect in
            style.fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: DS.TextInput.tokenRadius, yRadius: DS.TextInput.tokenRadius).fill()
            text.draw(
                in: CGRect(
                    x: DS.TextInput.tokenInset, y: DS.TextInput.tokenInset / 2,
                    width: size.width - DS.TextInput.tokenInset * 2, height: size.height - DS.TextInput.tokenInset))
            return true
        }
        #else
        image = UIGraphicsImageRenderer(size: size).image { _ in
            style.fill.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: DS.TextInput.tokenRadius).fill()
            text.draw(
                in: CGRect(
                    x: DS.TextInput.tokenInset, y: DS.TextInput.tokenInset / 2,
                    width: size.width - DS.TextInput.tokenInset * 2, height: size.height))
        }
        #endif
        bounds = CGRect(
            x: 0, y: style.font.descender - DS.TextInput.tokenInset / 2, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) { nil }
}
