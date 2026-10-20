import SwiftUI

/// The icon picker over stand-in icons: the emblem on each accent palette's tile, with a plugin's
/// set and a Mac-only one to show the badge and the note.
struct GalleryIconThemePicker: View {
    @State private var selection = "original"

    var body: some View {
        IconThemePicker("App icon", selection: $selection, options: Self.options)
    }

    static let options: [IconThemeOption<String>] =
        DSAccentPalette.all.map { palette in
            IconThemeOption(
                id: palette.id, title: palette.name,
                lightImage: tile(palette, scheme: .light), darkImage: tile(palette, scheme: .dark))
        } + [
            IconThemeOption(
                id: "set:sunset", title: "Sunset", lightImage: tile(.ember, scheme: .dark),
                darkImage: tile(.ember, scheme: .dark), badge: "Sunset Pack", note: "Mac only")
        ]

    /// A stand-in icon: the emblem on a squircle in the palette's accent.
    private static func tile(_ palette: DSAccentPalette, scheme: ColorScheme) -> Image {
        let side: CGFloat = 64
        let view = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            .fill(.dsAccent)
            .overlay {
                NativeMark()
                    .fill(.dsTextOnAccent)
                    .padding(side * 0.2)
            }
            .frame(width: side, height: side)
            .dsAccentPalette(palette)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return Image(systemName: "app") }
        return Image(decorative: image, scale: 2)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Gallery - Icon theme picker") {
    DSPreviewPair {
        GalleryIconThemePicker()
    }
}
#endif
