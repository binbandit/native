import AppKit
import SwiftUI

/// Every token and component, in light and dark side by side, for review. Open it from anywhere
/// with `DesignSystemGallery.showWindow()` (e.g. a debug menu item), or use the "Gallery" preview.
public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                DesignSystemGalleryColumn()
                    .environment(\.colorScheme, .light)
                DesignSystemGalleryColumn()
                    .environment(\.colorScheme, .dark)
            }
        }
        .frame(minWidth: 1280, minHeight: 720)
    }

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
}

/// One appearance's column of the gallery.
struct DesignSystemGalleryColumn: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text(colorScheme == .dark ? "Dark" : "Light")
                .font(.dsTitle)
                .foregroundStyle(.dsTextPrimary)
            GallerySection("Colors", source: "Factory core-ui v2 (\"Factory\" preset), Conductor statuses") {
                GalleryColors()
            }
            GallerySection("Typography", source: "Geist / Geist Mono, Factory scale") {
                GalleryTypography()
            }
            GallerySection("Spacing, radii, elevation", source: "Factory spacing, Conductor radii") {
                GalleryMetrics()
            }
            GallerySection("Sidebar", source: "Factory top half, Conductor projects and tasks, translucent") {
                GallerySidebar()
            }
            GallerySection("Task status", source: "Conductor workspace statuses and dot-grid loaders") {
                GalleryStatus()
            }
            GallerySection("Composer", source: "Factory composer") {
                GalleryComposer()
            }
            GallerySection("Controls", source: "Factory buttons, Kbd; Conductor badges, cards, empty states") {
                GalleryControls()
            }
            GallerySection("Launch", source: "Factory startup animation, Native's marks") {
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
