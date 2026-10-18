import CoreText
import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// How code is set wherever it shows (code blocks, diffs, tool output): the user's monospaced
// family, size, line height and ligatures, Geist Mono at 12pt by default. Views set code with
// `.codeTextStyle(_:)` rather than `.dsMono`, so one setting changes every place at once.

/// The user's code font.
public nonisolated struct DSCodeFont: Hashable, Sendable {
    /// An installed monospaced family; empty for Native's own, Geist Mono.
    public var family: String
    public var size: Double
    /// Line height as a multiple of the size.
    public var lineHeight: Double
    /// Programming ligatures (`->` as an arrow), in fonts that have them.
    public var ligatures: Bool

    public init(family: String = "", size: Double = 12, lineHeight: Double = 1.5, ligatures: Bool = true) {
        self.family = family
        self.size = size
        self.lineHeight = lineHeight
        self.ligatures = ligatures
    }

    public static let standard = DSCodeFont()
    public static let defaultFamilyName = "Geist Mono"
    public static let sizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 18]
    public static let lineHeights: [Double] = [1.2, 1.35, 1.5, 1.65, 1.8]

    /// Installed monospaced font families, by name.
    @MainActor public static var installedFamilies: [String] {
        #if canImport(AppKit)
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        #else
        let families = Set(
            UIFont.familyNames.filter { family in
                UIFont.fontNames(forFamilyName: family).contains { name in
                    UIFont(name: name, size: 12)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true
                }
            })
        #endif
        return families.filter { !$0.hasPrefix(".") && $0 != defaultFamilyName }.sorted()
    }

    /// The font for code `offset` points off the chosen size (diffs and tool output are a point smaller).
    func platformFont(offset: Double) -> DSPlatformFont {
        let size = max(size + offset, 8)
        var font = DSTypography.platformFont(size: size, design: .mono)
        #if canImport(AppKit)
        if !family.isEmpty, let chosen = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
            font = chosen
        }
        guard !ligatures else { return font }
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: Self.noLigatures])
        return NSFont(descriptor: descriptor, size: size) ?? font
        #else
        if !family.isEmpty, let chosen = UIFont(name: family, size: size) {
            font = chosen
        }
        guard !ligatures else { return font }
        return UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: Self.noLigatures]), size: size)
        #endif
    }

    /// OpenType features that turn off common ligatures and contextual alternates (where coding
    /// fonts keep most of theirs).
    private static var noLigatures: [[DSPlatformFontDescriptor.FeatureKey: Int]] {
        #if canImport(AppKit)
        [
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        #else
        [
            [.type: kLigaturesType, .selector: kCommonLigaturesOffSelector],
            [.type: kContextualAlternatesType, .selector: kContextualAlternatesOffSelector],
        ]
        #endif
    }
}

nonisolated extension EnvironmentValues {
    /// The code font. Set it with `.dsCodeFont(_:)`; use it with `.codeTextStyle(_:)`.
    @Entry public var dsCodeFont: DSCodeFont = .standard
}

/// Where code is set, which decides its size relative to the user's choice.
public enum DSCodeTextRole: Sendable {
    /// Code blocks in Markdown: the chosen size.
    case block
    /// Diffs and tool output: a point smaller, as they sit inside other content.
    case compact
}

extension View {
    /// Sets the code font for this window. Put it on each window's root.
    public func dsCodeFont(_ font: DSCodeFont) -> some View {
        environment(\.dsCodeFont, font)
    }

    /// Sets this code in the user's code font, size and line height.
    public func codeTextStyle(_ role: DSCodeTextRole = .block) -> some View {
        modifier(CodeTextStyle(role: role))
    }
}

private struct CodeTextStyle: ViewModifier {
    let role: DSCodeTextRole

    @Environment(\.dsCodeFont) private var codeFont

    func body(content: Content) -> some View {
        let offset: Double = role == .block ? 0 : -1
        let size = codeFont.size + offset
        content
            .font(Font(codeFont.platformFont(offset: offset) as CTFont))
            // Text's own line height is about 1.2 times its size; the rest of the multiple is spacing.
            .lineSpacing(max(0, size * (codeFont.lineHeight - 1.2)))
    }
}

#if canImport(AppKit)
typealias DSPlatformFontDescriptor = NSFontDescriptor
#else
typealias DSPlatformFontDescriptor = UIFontDescriptor
#endif
