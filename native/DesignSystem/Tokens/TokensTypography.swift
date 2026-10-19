import CoreText
import SwiftUI
import Synchronization

// Typography tokens. The UI is set in Geist (Vercel, SIL OFL 1.1; the license ships next to the
// files in `Fonts/`), and the type is a large part of the look, so the official variable fonts
// (Geist 1.401) are bundled and registered for the process the first time a token is read. If that
// fails, every token falls back to the system font at the same size and weight.
//
// UI text is 12pt, with 13pt for sidebar rows and the composer (the macOS sidebar size), in weights
// 300, 400, 450, 500 and 600.

extension Font {
    /// 10pt: relative times, counts.
    public nonisolated static let dsMicro = DSTypography.font(size: 10)
    /// 11pt: shortcut hints, badges, secondary metadata.
    public nonisolated static let dsCaption = DSTypography.font(size: 11)
    public nonisolated static let dsCaptionMedium = DSTypography.font(size: 11, weight: .medium)
    /// 12pt: the default UI and control text.
    public nonisolated static let dsBody = DSTypography.font(size: 12)
    public nonisolated static let dsBodyMedium = DSTypography.font(size: 12, weight: .medium)
    /// 13pt: sidebar rows and the composer's text.
    public nonisolated static let dsCallout = DSTypography.font(size: 13)
    /// 13pt at 450, the weight of a read task title.
    public nonisolated static let dsCalloutBook = DSTypography.font(size: 13, weight: .book)
    public nonisolated static let dsCalloutMedium = DSTypography.font(size: 13, weight: .medium)
    /// 13pt semibold: project names and unread task titles.
    public nonisolated static let dsCalloutSemibold = DSTypography.font(size: 13, weight: .semibold)
    /// 14pt medium: card and dialog titles.
    public nonisolated static let dsHeadline = DSTypography.font(size: 14, weight: .medium)
    /// 16pt medium.
    public nonisolated static let dsTitle3 = DSTypography.font(size: 16, weight: .medium)
    /// 20pt medium.
    public nonisolated static let dsTitle2 = DSTypography.font(size: 20, weight: .medium)
    /// 24pt medium.
    public nonisolated static let dsTitle = DSTypography.font(size: 24, weight: .medium)

    /// 10pt Geist Mono: keyboard hints.
    public nonisolated static let dsMonoMicro = DSTypography.font(size: 10, design: .mono)
    /// 11pt Geist Mono: code and tool output.
    public nonisolated static let dsMonoCaption = DSTypography.font(size: 11, design: .mono)
    /// 12pt Geist Mono.
    public nonisolated static let dsMono = DSTypography.font(size: 12, design: .mono)

    /// A one-off size or weight from the same families. Prefer the named tokens.
    public nonisolated static func ds(
        _ size: CGFloat,
        weight: DSTypography.Weight = .regular,
        design: DSTypography.Design = .sans
    ) -> Font {
        DSTypography.font(size: size, weight: weight, design: design)
    }
}

extension DS {
    /// Letter spacing, in points at the text's size.
    public nonisolated enum Tracking {
        /// -0.01em at 12pt.
        public static let tight: CGFloat = -0.12
        /// Sidebar links and the update button (-0.02em at 13pt).
        public static let snug: CGFloat = -0.26
        /// Uppercase mono badges.
        public static let wide: CGFloat = 0.6
    }
}

/// Builds the typography tokens' fonts, and AppKit fonts for text views that need the same type.
public nonisolated enum DSTypography {
    public enum Design: Hashable, Sendable {
        case sans, mono
    }

    /// Font weights on the variable `wght` axis.
    public enum Weight: CGFloat, Hashable, Sendable {
        case light = 300
        case regular = 400
        /// A touch heavier than regular, for read titles.
        case book = 450
        case medium = 500
        case semibold = 600
        case bold = 700

        var system: DSPlatformFont.Weight {
            switch self {
            case .light: .light
            case .regular, .book: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    /// The platform font behind a token, for text views outside SwiftUI (the composer's editor,
    /// code views) and for metrics such as cap height.
    public static func platformFont(size: CGFloat, weight: Weight = .regular, design: Design = .sans) -> DSPlatformFont
    {
        guard let geist else {
            return switch design {
            case .sans: .systemFont(ofSize: size, weight: weight.system)
            case .mono: .monospacedSystemFont(ofSize: size, weight: weight.system)
            }
        }
        // 'wght' as a four-character code.
        let variation = [0x7767_6874: weight.rawValue]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            design == .sans ? geist.sans : geist.mono, [kCTFontVariationAttribute as String: variation] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as DSPlatformFont
    }

    #if canImport(AppKit)
    /// The `NSFont` behind a token; `platformFont` under its AppKit name.
    public static func nsFont(size: CGFloat, weight: Weight = .regular, design: Design = .sans) -> NSFont {
        platformFont(size: size, weight: weight, design: design)
    }
    #endif

    static func font(size: CGFloat, weight: Weight = .regular, design: Design = .sans) -> Font {
        let key = Key(size: size, weight: weight, design: design)
        if let font = cache.withLock({ $0[key] }) {
            return font
        }
        let font = Font(platformFont(size: size, weight: weight, design: design) as CTFont)
        cache.withLock { $0[key] = font }
        return font
    }

    private struct Key: Hashable {
        let size: CGFloat
        let weight: Weight
        let design: Design
    }

    /// Fonts already built, so one-off `Font.ds(...)` calls in view bodies stay cheap.
    private static let cache = Mutex<[Key: Font]>([:])

    /// The bundled Geist and Geist Mono, registered for the process on first use so text views and
    /// font names find them too; nil when either is missing or won't register. Fonts are made from
    /// these rather than by family name, which searches every font installed for each one.
    private static let geist: GeistFonts? = {
        let descriptors = ["Geist-VariableFont_wght", "GeistMono-VariableFont_wght"].compactMap {
            name -> CTFontDescriptor? in
            guard let url = resources.url(forResource: name, withExtension: "ttf") else { return nil }
            var error: Unmanaged<CFError>?
            guard
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                    || error.map({ CFErrorGetCode($0.takeRetainedValue()) })
                        == CTFontManagerError.alreadyRegistered.rawValue
            else { return nil }
            return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
        }
        guard descriptors.count == 2 else { return nil }
        return GeistFonts(sans: descriptors[0], mono: descriptors[1])
    }()

    /// CoreText descriptors are immutable, so any thread may use them.
    private struct GeistFonts: @unchecked Sendable {
        let sans: CTFontDescriptor
        let mono: CTFontDescriptor
    }

    /// Where the fonts are bundled: the app today, this module's bundle once it's a package target.
    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}
