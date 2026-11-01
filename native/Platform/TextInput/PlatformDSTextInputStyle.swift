import SwiftUI

#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Resolves SwiftUI tokens for both native editors, including appearance changes after creation.
struct PlatformDSTextInputStyle: Equatable {
    let font = DSTypography.platformFont(size: DS.TextInput.fontSize)
    let foreground: DSPlatformColor
    let secondary: DSPlatformColor
    let fill: DSPlatformColor
    let accent: DSPlatformColor

    init(environment: EnvironmentValues) {
        foreground = Self.color(.dsTextPrimary, environment)
        secondary = Self.color(.dsTextTertiary, environment)
        fill = Self.color(.dsFill, environment)
        accent = Self.color(.dsAccent, environment)
    }

    private static func color(_ color: Color, _ environment: EnvironmentValues) -> DSPlatformColor {
        #if canImport(AppKit)
        NSColor(cgColor: color.resolve(in: environment).cgColor) ?? .labelColor
        #else
        UIColor(cgColor: color.resolve(in: environment).cgColor)
        #endif
    }

    var lineHeight: CGFloat {
        #if canImport(AppKit)
        NSLayoutManager().defaultLineHeight(for: font) + DS.TextInput.lineSpacing
        #else
        font.lineHeight + DS.TextInput.lineSpacing
        #endif
    }

    var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
    }

    func attributed(_ document: TextInputDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in document.runs {
            switch run {
            case .text(let text): result.append(NSAttributedString(string: text, attributes: attributes))
            case .mention(let path):
                result.append(NSAttributedString(attachment: PlatformDSTextInputMention(path: path, style: self)))
            }
        }
        if result.length > 0 { result.addAttributes(attributes, range: NSRange(location: 0, length: result.length)) }
        return result
    }

    static func document(_ storage: NSAttributedString) -> TextInputDocument {
        var runs: [TextInputDocument.Run] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let mention = value as? PlatformDSTextInputMention {
                runs.append(.mention(path: mention.path))
            } else {
                runs.append(.text(storage.attributedSubstring(from: range).string))
            }
        }
        return TextInputDocument(runs: runs)
    }
}
