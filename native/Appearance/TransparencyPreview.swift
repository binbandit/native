import SwiftUI

/// A small window over a busy wallpaper, drawn at the current transparency: the sidebar, a popover
/// and the floating composer, one of each kind of translucent layer. It uses the same design-system
/// surfaces as the app, so what it shows is what the app does.
struct TransparencyPreview: View {
    @Environment(\.dsTransparency) private var transparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        ZStack(alignment: .topLeading) {
            wallpaper
            HStack(spacing: 0) {
                sidebar
                    .frame(width: Metrics.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .dsSidebarBackground(blending: .withinWindow)
                SeparatorLine(axis: .vertical)
                transcript
            }
            popover
                .offset(x: Metrics.popoverOffset.width, y: Metrics.popoverOffset.height)
        }
        .frame(height: Metrics.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .animation(.dsStandard, value: transparency)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the sidebar, a popover and the composer at \(transparency.title) transparency")
    }

    /// Bold diagonal bands, the worst case for anything see-through.
    private var wallpaper: some View {
        let colors: [Color] = [.dsChart1, .dsAttention, .dsChart3, .dsTextPrimary, .dsChart2, .dsInfo, .dsMerged]
        let band = 1 / Double(colors.count)
        let stops = colors.enumerated().flatMap { index, color in
            [
                Gradient.Stop(color: color, location: Double(index) * band),
                Gradient.Stop(color: color, location: Double(index + 1) * band),
            ]
        }
        return LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            row("New Task", systemImage: "plus")
            row("Pull Requests", systemImage: "arrow.triangle.pull")
            row("Workflows", systemImage: "point.3.connected.trianglepath.dotted")
            Text("Projects")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.md)
            row("Sidebar polish", systemImage: "circle.dotted", isSelected: true)
            row("Fix flaky test", systemImage: "circle")
        }
        .padding(DS.Space.sm)
    }

    private func row(_ title: String, systemImage: String, isSelected: Bool = false) -> some View {
        Label(title, systemImage: systemImage)
            .font(.dsCallout)
            .foregroundStyle(.dsTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.md)
            .frame(maxWidth: .infinity, minHeight: DS.Size.listRow, alignment: .leading)
            .background(isSelected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
    }

    private var transcript: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Moved the sidebar rows onto the shared hover and selection fills, so they read on any wallpaper.")
                Text("Ran the tests: 214 passed. The gallery shows both appearances.")
                Text("Next I can tighten the composer’s spacing, or leave it for review.")
                Text("The composer floats over this text, so its glass shows what scrolls beneath it.")
                Text("Popovers and toasts sit on the overlay color over a blur of the window.")
            }
            .font(.dsCallout)
            .foregroundStyle(.dsTextPrimary)
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ComposerSurface(isFloating: true) {
                Text("Ask for a change…")
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextTertiary)
                    .padding(DS.Composer.textInsets)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.lg)
        }
        .background(.dsBackground)
    }

    private var popover: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Context")
                .font(.dsCalloutMedium)
                .foregroundStyle(.dsTextPrimary)
            Text("62% used · 81k of 131k tokens")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        }
        .padding(DS.Space.lg)
        .frame(width: Metrics.popoverWidth, alignment: .leading)
        .dsOverlayBackground(in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
    }

    private enum Metrics {
        static let height: CGFloat = 220
        static let sidebarWidth: CGFloat = 168
        static let popoverWidth: CGFloat = 200
        /// Straddles the sidebar's edge, so it covers both the wallpaper and the transcript.
        static let popoverOffset = CGSize(width: 84, height: 96)
    }
}

#Preview("Transparency preview") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ForEach(DSTransparency.allCases) { level in
                TransparencyPreview()
                    .dsTransparency(level)
            }
        }
        .frame(width: 640)
        .padding(DS.Space.xl)
    }
}
