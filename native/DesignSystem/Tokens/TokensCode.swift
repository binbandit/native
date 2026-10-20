import CodeThemes
import SwiftUI

// Colors for code: syntax roles in code blocks and diffs come from the code theme the user picks
// for each appearance (`Packages/CodeThemes`, Native by default). Native draws on the design
// system's own surfaces, so it follows the tones (Paper or Wool, Standard or True Black) with its
// text roles adjusted to keep their contrast there; other themes bring their own background. Roles a
// theme sets strong (Native's dark keywords) are set in the code font's semibold.

/// The code theme chosen for light mode and for dark mode: a built-in theme or a plugin's.
public nonisolated struct DSCodeThemes: Hashable, Sendable {
    public var light: CodeTheme
    public var dark: CodeTheme

    public init(light: CodeTheme, dark: CodeTheme) {
        self.light = light
        self.dark = dark
    }

    public static let native = DSCodeThemes(light: .native, dark: .native)
}

nonisolated extension EnvironmentValues {
    /// The code themes code blocks and diffs draw with. Set it with `.dsCodeThemes(_:)`.
    @Entry public var dsCodeThemes: DSCodeThemes = .native
}

extension View {
    /// Sets the code themes for this window's code blocks and diffs. Put it on each window's root.
    public func dsCodeThemes(_ themes: DSCodeThemes) -> some View {
        environment(\.dsCodeThemes, themes)
    }
}

/// The code colors for one environment: the chosen theme's palette for its appearance.
public nonisolated struct DSCodeColors: Sendable {
    /// What code draws on when the theme is Native.
    public enum Surface: Sendable {
        /// Code blocks: the sunken surface.
        case sunken
        /// Diffs: the plain surface.
        case surface
    }

    public let palette: CodePalette
    /// Native, which draws on the design system's surfaces rather than a background of its own.
    public let isNative: Bool

    public init(_ environment: EnvironmentValues, on surface: Surface) {
        let appearance: CodeAppearance = environment.colorScheme == .dark ? .dark : .light
        let theme = appearance == .dark ? environment.dsCodeThemes.dark : environment.dsCodeThemes.light
        // A theme without this appearance falls back to Native.
        let chosen = theme.palette(for: appearance).map { (theme.id, $0) }
        guard let resolved = chosen ?? CodeTheme.native.palette(for: appearance).map({ (CodeTheme.native.id, $0) })
        else { preconditionFailure("Native has a palette for both appearances") }
        let (themeID, palette) = resolved
        isNative = themeID == CodeTheme.native.id
        if isNative {
            let fill: Color = surface == .sunken ? .dsSurfaceSunken : .dsSurface
            self.palette = palette.preservingContrast(on: CodeColor(fill.resolve(in: environment)))
        } else {
            self.palette = palette
        }
    }

    public func color(_ role: CodeTokenRole) -> Color {
        Color(palette[role])
    }

    /// Highlighted segments as styled text. Strong roles are marked with `DSCodeStrongAttribute`
    /// for text views that pick the font themselves; SwiftUI text gets `strongFont` on them as well.
    public func text(_ segments: [CodeSegment], strongFont: Font?) -> AttributedString {
        var text = AttributedString()
        for segment in segments {
            var run = AttributedString(segment.text)
            run.foregroundColor = color(segment.role)
            if palette.strong.contains(segment.role) {
                run[DSCodeStrongAttribute.self] = true
                run.font = strongFont
            }
            text += run
        }
        return text
    }

    /// Highlighted segments for a platform text view, which sets the strong runs' font itself.
    public func text(_ segments: [CodeSegment]) -> AttributedString {
        text(segments, strongFont: nil)
    }
}

/// Marks code a theme sets strong (`CodePalette.strong`). A platform text view sets these runs in
/// `DSCodeFont.weighted(_:_:)` of its font, as SwiftUI text does through `.codeTextStyle(_:)`.
public enum DSCodeStrongAttribute: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "native.codeStrong"
}

/// The background code draws on: the code theme's own, or for Native the given design-system fill.
public nonisolated struct DSCodeBackground: ShapeStyle, Hashable {
    let surface: DSCodeColors.Surface

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let colors = DSCodeColors(environment, on: surface)
        if colors.isNative {
            return (surface == .sunken ? Color.dsSurfaceSunken : .dsSurface).resolve(in: environment)
        }
        return Color(colors.palette.background).resolve(in: environment)
    }
}

extension ShapeStyle where Self == DSCodeBackground {
    /// Behind code blocks: the code theme's background, or the sunken surface for Native.
    public static var dsCodeBlockBackground: DSCodeBackground { DSCodeBackground(surface: .sunken) }
    /// Behind diffs: the code theme's background, or the surface for Native.
    public static var dsDiffBackground: DSCodeBackground { DSCodeBackground(surface: .surface) }
}

/// Code drawn in the user's code theme. Set the font around it (`.dsMono`).
public struct HighlightedCode: View {
    let code: String
    let language: CodeLanguage?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.dsCodeThemes) private var codeThemes
    @Environment(\.dsCodeStrongFont) private var strongFont
    /// Colors from a background thread, kept while the code changes (a block in a streaming reply).
    @State private var highlighter = LiveCodeHighlighter()

    /// - Parameter language: A Markdown fence's info string (`swift`, `ts`…), or nil for a file's
    ///   extension to decide via `CodeLanguage.forPath`; unknown languages draw plain.
    public init(_ code: String, language: String?) {
        self.code = code
        self.language = language.flatMap(CodeLanguage.named)
    }

    public init(_ code: String, path: String) {
        self.code = code
        language = CodeLanguage.forPath(path)
    }

    public var body: some View {
        let colors = DSCodeColors(
            .code(colorScheme: colorScheme, lightTone: lightTone, darkTone: darkTone, themes: codeThemes), on: .sunken)
        // Plain or the colors there are at once; the highlighter brings the rest.
        let segments = highlighter.segments(for: code, language: language)
        if let segments {
            Text(colors.text(segments, strongFont: strongFont))
        } else {
            Text(verbatim: code)
                .foregroundStyle(colors.color(.foreground))
        }
    }
}

extension EnvironmentValues {
    /// Just what code colors depend on, so views read these values rather than the whole
    /// environment.
    nonisolated static func code(
        colorScheme: ColorScheme, lightTone: DSLightTone, darkTone: DSDarkTone, themes: DSCodeThemes
    )
        -> EnvironmentValues
    {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        environment.dsLightTone = lightTone
        environment.dsDarkTone = darkTone
        environment.dsCodeThemes = themes
        return environment
    }
}

extension Color {
    nonisolated init(_ color: CodeColor) {
        self.init(
            .sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
            opacity: Double(color.alpha) / 255)
    }
}

extension CodeColor {
    /// A resolved SwiftUI color in 8-bit sRGB.
    nonisolated init(_ resolved: Color.Resolved) {
        func channel(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        // `Color.Resolved` keeps linear components; its sRGB description is the gamma-encoded one.
        let srgb = resolved.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB) ?? resolved.cgColor.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent, options: nil)
        let components = srgb?.components ?? [0, 0, 0, 1]
        self.init(
            red: channel(Float(components[0])),
            green: channel(Float(components.count > 2 ? components[1] : components[0])),
            blue: channel(Float(components.count > 2 ? components[2] : components[0])),
            alpha: channel(resolved.opacity))
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Highlighted code") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HighlightedCode(
                """
                let blocks = MarkdownNode.blocks(from: source)
                for block in blocks ?? [] {
                    print(block.kind) // the innermost block
                }
                """, language: "swift")
            HighlightedCode("swift test --filter PromptQueueTests && echo \"done\"", language: "bash")
            HighlightedCode("{\"sessionId\": \"59be18cd\", \"title\": null}", path: "session.json")
        }
        .codeTextStyle()
        .padding(DS.Space.md)
        .background(.dsCodeBlockBackground, in: .rect(cornerRadius: DS.Radius.card))
        .frame(width: 480, alignment: .leading)
    }
}
#endif
