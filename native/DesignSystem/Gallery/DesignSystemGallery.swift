import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Every token and component, in light and dark side by side, for review. Open it from anywhere
/// with `DesignSystemGallery.showWindow()` (e.g. a debug menu item), or use the "Gallery" preview.
public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            // Side by side where there's room, stacked on a narrower iPad.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) { columns }
                VStack(spacing: 0) { columns }
            }
        }
        #if os(macOS)
        .frame(minWidth: 1280, minHeight: 720)
        #endif
    }

    @ViewBuilder private var columns: some View {
        DesignSystemGalleryColumn()
            .environment(\.colorScheme, .light)
        DesignSystemGalleryColumn()
            .environment(\.colorScheme, .dark)
    }

    #if canImport(AppKit)
    /// Opens the gallery in its own window, or brings the open one forward.
    public static func showWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier == windowID }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: DesignSystemGallery()))
        window.identifier = windowID
        window.title = "Design System"
        window.setContentSize(NSSize(width: 1300, height: 900))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private static let windowID = NSUserInterfaceItemIdentifier("native.design-system-gallery")
    #endif
}

/// One appearance's column of the gallery.
struct DesignSystemGalleryColumn: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text(colorScheme == .dark ? "Dark" : "Light")
                .font(.dsTitle)
                .foregroundStyle(.dsTextPrimary)
            GallerySection("Brand", source: "Native's emblem, lockups, nightly sky and moon") {
                GalleryBrand()
            }
            GallerySection("Accent palettes", source: "One per app-icon theme, set with .dsAccentPalette(themeID:)") {
                GalleryAccentPalettes()
            }
            GallerySection("Colors", source: "the reference app core-ui v2 neutrals, the reference app statuses, CVD-safe chart series") {
                GalleryColors()
            }
            GallerySection("Typography", source: "Geist / Geist Mono, the reference app scale") {
                GalleryTypography()
            }
            GallerySection("Spacing, radii, elevation", source: "the reference app spacing, the reference app radii") {
                GalleryMetrics()
            }
            GallerySection("Sidebar", source: "the reference app top half, the reference app projects and tasks, translucent") {
                GallerySidebar()
            }
            GallerySection("Task status", source: "the reference app workspace statuses and dot-grid loaders") {
                GalleryStatus()
            }
            GallerySection("Composer", source: "the reference app composer") {
                GalleryComposer()
            }
            GallerySection("Controls", source: "the reference app buttons, Kbd; the reference app badges, cards") {
                GalleryControls()
            }
            GallerySection("Patterns", source: "One per situation (docs/product-quality.md)") {
                GalleryPatterns()
            }
            GallerySection("Launch", source: "The emblem assembling itself") {
                LaunchAnimationView()
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: DS.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsSeparator)
                    }
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 640, alignment: .leading)
        .background(.dsBackground)
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    let source: String
    @ViewBuilder var content: Content

    init(_ title: String, source: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.source = source
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text(source)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            content
        }
    }
}

#Preview("Gallery") {
    DesignSystemGallery()
}
