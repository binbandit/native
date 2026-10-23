import SwiftUI

/// Still status marks on the loader's 240pt grid, so failure occupies the same glyph slot as work.
public struct DotGridMark: View {
    public enum Mark: Sendable {
        case failed
    }

    let mark: Mark

    public init(_ mark: Mark) {
        self.mark = mark
    }

    public var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 240
            let radius = 22 * unit
            let origin = CGPoint(x: (size.width - 240 * unit) / 2, y: (size.height - 240 * unit) / 2)
            for (x, y) in [(50.0, 50.0), (190.0, 50.0), (120.0, 120.0), (50.0, 190.0), (190.0, 190.0)] {
                let rect = CGRect(
                    x: origin.x + x * unit - radius, y: origin.y + y * unit - radius,
                    width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Dot grid - Failed") {
    DSPreviewPair {
        DotGridMark(.failed)
            .foregroundStyle(.dsDanger)
            .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
    }
}
