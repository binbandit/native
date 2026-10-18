import SwiftUI

/// The status bar at three widths: everything, then the innermost items dropping out.
struct GalleryStatusBar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach([CGFloat(560), 380, 220], id: \.self) { width in
                bar.frame(width: width)
            }
        }
    }

    private var bar: some View {
        StatusBarSurface {
            Button {
            } label: {
                HStack(spacing: DS.Space.sm) {
                    StatusIndicator(status: .working, size: DS.Size.statusGlyph)
                    Text("2 working")
                    Text("4m").foregroundStyle(.dsTextQuaternary)
                }
            }
            .buttonStyle(.statusBarSegment())
            Button {
            } label: {
                HStack(spacing: DS.Space.sm) {
                    StatusIndicator(status: .needsPermission, size: DS.Size.statusGlyph)
                    Text("1 needs you")
                }
            }
            .buttonStyle(.statusBarSegment(.attention))
        } trailing: {
            Button {
            } label: {
                HStack(spacing: DS.Space.xs) {
                    StatusBarGlyph("cup.and.saucer")
                    Text("Off")
                }
            }
            .buttonStyle(.statusBarSegment())
            Button {
            } label: {
                HStack(spacing: DS.Space.xs) {
                    StatusBarGlyph("memorychip")
                    Text("764.1 MB")
                    StatusBarDivider()
                    StatusBarGlyph("cpu")
                    Text("3%")
                }
            }
            .buttonStyle(.statusBarSegment(isActive: true))
        }
    }
}
