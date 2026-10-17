import SwiftUI

/// The nightly build's tell: the crescent moon from the Nightly app icon, sized for a sidebar
/// header or title (10-11pt). Draws in the current foreground style; pair it with
/// `.dsTextTertiary` so it stays a quiet hint. The design system doesn't know the release
/// channel, so show it only for nightly builds.
public struct NightlyMark: View {
    let size: CGFloat

    /// - Parameter size: The moon's height.
    public init(size: CGFloat = 10) {
        self.size = size
    }

    public var body: some View {
        Crescent()
            .frame(width: size * Crescent.aspectRatio, height: size)
            .help("Nightly build")
            .accessibilityElement()
            .accessibilityLabel("Nightly build")
            .accessibilityAddTraits(.isImage)
    }
}

/// The Nightly icon's moon (`night-sky.svg`): a disk with an overlapping disk cut away, opening to
/// the right, fitted to the rect's height.
nonisolated struct Crescent: Shape {
    // In the icon's units: the outer disk's center and radius, then the cut's. The crescent's tips
    // sit on the cut's vertical diameter.
    private static let outer = (x: 814.45, y: 174.0, r: 45.0)
    private static let cut = (x: 833.0, y: 174.0, r: 41.0)
    private static let bounds = CGRect(x: outer.x - outer.r, y: outer.y - outer.r, width: cut.x - (outer.x - outer.r), height: outer.r * 2)

    /// Width over height.
    static let aspectRatio = bounds.width / bounds.height

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.height / Self.bounds.height, rect.width / Self.bounds.width)
        let origin = CGPoint(
            x: rect.midX - Self.bounds.width * scale / 2,
            y: rect.midY - Self.bounds.height * scale / 2
        )
        func disk(_ circle: (x: Double, y: Double, r: Double)) -> Path {
            Path(ellipseIn: CGRect(
                x: origin.x + (circle.x - circle.r - Self.bounds.minX) * scale,
                y: origin.y + (circle.y - circle.r - Self.bounds.minY) * scale,
                width: circle.r * 2 * scale,
                height: circle.r * 2 * scale
            ))
        }
        return disk(Self.outer).subtracting(disk(Self.cut))
    }
}

#Preview("Nightly mark") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            NativeLockup(size: 13)
            NightlyMark()
                .foregroundStyle(.dsTextTertiary)
        }
        .foregroundStyle(.dsTextPrimary)
    }
}
