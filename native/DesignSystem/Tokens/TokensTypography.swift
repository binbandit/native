import CoreText
import SwiftUI
import Synchronization

// Typography tokens. the reference app and the reference app both set their UI in Geist (Vercel, SIL OFL 1.1; the
// license ships next to the files in `Fonts/`), and the type is a large part of their look, so the
// official variable fonts (Geist 1.401) are bundled and registered for the process the first time
// a token is read. If that fails, every token falls back to the system font at the same size and
// weight.
//
// Sizes follow the reference app's core-ui v2 scale (`--core-v2-font-size-*`, UI text 12px), with 13px for
// sidebar rows and the composer (the reference app's `--font-size-sm`, also the macOS sidebar size) and
// the reference app's weights (300/400/500) plus the reference app's 450 and 600. CSS px map 1:1 to points.

extension Font {
    /// 10pt: relative times, counts (the reference app `text-3xs`).
    public nonisolated static let dsMicro = DSTypography.font(size: 10)
    /// 11pt: shortcut hints, badges, secondary metadata (the reference app `font-size-11`).
    public nonisolated static let dsCaption = DSTypography.font(size: 11)
    public nonisolated static let dsCaptionMedium = DSTypography.font(size: 11, weight: .medium)
    /// 12pt: the reference app's default UI and control text (`controlText`).
    public nonisolated static let dsBody = DSTypography.font(size: 12)
    public nonisolated static let dsBodyMedium = DSTypography.font(size: 12, weight: .medium)
    /// 13pt: sidebar rows and the composer's text (the reference app `--font-size-sm`).
    public nonisolated static let dsCallout = DSTypography.font(size: 13)
    /// 13pt at the reference app's 450, the weight of a read task title.
    public nonisolated static let dsCalloutBook = DSTypography.font(size: 13, weight: .book)
    public nonisolated static let dsCalloutMedium = DSTypography.font(size: 13, weight: .medium)
    /// 13pt semibold: project names and unread task titles (the reference app `font-semibold`).
    public nonisolated static let dsCalloutSemibold = DSTypography.font(size: 13, weight: .semibold)
    /// 14pt medium: card and dialog titles.
    public nonisolated static let dsHeadline = DSTypography.font(size: 14, weight: .medium)
    /// 16pt medium.
    public nonisolated static let dsTitle3 = DSTypography.font(size: 16, weight: .medium)
    /// 20pt medium.
    public nonisolated static let dsTitle2 = DSTypography.font(size: 20, weight: .medium)
    /// 24pt medium.
    public nonisolated static let dsTitle = DSTypography.font(size: 24, weight: .medium)

    /// 10pt Geist Mono: keyboard hints (the reference app `Kbd`).
    public nonisolated static let dsMonoMicro = DSTypography.font(size: 10, design: .mono)
    /// 11pt Geist Mono: code and tool output (the reference app's default code size).
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
        /// the reference app's `--core-v2-tracking-tight` (-0.01em) at 12pt.
        public static let tight: CGFloat = -0.12
        /// the reference app's sidebar link and update button (-0.26px at 13px, -0.02em).
        public static let snug: CGFloat = -0.26
        /// the reference app's uppercase mono badges (`tracking-wider`, 0.6px).
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
        /// the reference app's `font-450`: a touch heavier than regular, for read titles.
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
        guard isGeistAvailable else {
            return switch design {
            case .sans: .systemFont(ofSize: size, weight: weight.system)
            case .mono: .monospacedSystemFont(ofSize: size, weight: weight.system)
            }
        }
        // 'wght' as a four-character code.
        let variation = [0x7767_6874: weight.rawValue]
        let family = design == .sans ? "Geist" : "Geist Mono"
        #if canImport(AppKit)
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family, .variation: variation])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight.system)
        #else
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation,
        ])
        return UIFont(descriptor: descriptor, size: size)
        #endif
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

    /// Whether Geist is available; registers the bundled fonts on first use.
    private static let isGeistAvailable: Bool = {
        let urls = ["Geist-VariableFont_wght", "GeistMono-VariableFont_wght"].compactMap {
            resources.url(forResource: $0, withExtension: "ttf")
        }
        if !urls.isEmpty {
            // Already-registered fonts report an error per URL; availability is checked below.
            CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        }
        let families = Set(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
        return families.contains("Geist") && families.contains("Geist Mono")
    }()

    /// Where the fonts are bundled: the app today, this module's bundle once it's a package target.
    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}
