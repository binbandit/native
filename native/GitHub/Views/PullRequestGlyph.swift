import SwiftUI

/// The pull request glyphs (Lucide's git-pull-request family, drawn
/// here on its 24-point grid): SF Symbols has no open, draft or closed pull request glyph that
/// reads at 12 to 14 points.
nonisolated struct PullRequestGlyph: Shape {
    enum Kind {
        case open, draft, merged, closed
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        func circle(_ x: CGFloat, _ y: CGFloat) {
            path.addEllipse(
                in: CGRect(
                    x: rect.minX + (x - 3) * scale, y: rect.minY + (y - 3) * scale, width: 6 * scale, height: 6 * scale)
            )
        }
        func line(_ points: (CGFloat, CGFloat)...) {
            path.addLines(points.map { point($0.0, $0.1) })
        }

        switch kind {
        case .open:
            circle(5, 6)
            line((5, 9), (5, 21))
            circle(19, 18)
            line((15, 9), (12, 6), (15, 3))
            path.move(to: point(12, 6))
            path.addArc(tangent1End: point(19, 6), tangent2End: point(19, 15), radius: 2 * scale)
            path.addLine(to: point(19, 15))
        case .draft:
            circle(6, 6)
            line((6, 9), (6, 21))
            circle(18, 18)
            line((18, 6), (18, 5))
            line((18, 11), (18, 10))
        case .merged:
            circle(18, 18)
            circle(6, 6)
            path.move(to: point(6, 21))
            path.addLine(to: point(6, 9))
            path.addArc(tangent1End: point(6, 18), tangent2End: point(15, 18), radius: 9 * scale)
            path.addLine(to: point(15, 18))
        case .closed:
            circle(6, 6)
            line((6, 9), (6, 21))
            line((21, 3), (15, 9))
            line((21, 9), (15, 3))
            line((18, 11.5), (18, 15))
            circle(18, 18)
        }
        return path
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pull request glyphs") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xl) {
            ForEach([PullRequestGlyph.Kind.open, .draft, .merged, .closed], id: \.self) { kind in
                VStack(spacing: DS.Space.md) {
                    // The sizes the app draws them at, and a large one to check the geometry.
                    ForEach([12, 14, 48], id: \.self) { size in
                        PullRequestGlyph(kind: kind)
                            .stroke(
                                .dsTextPrimary, style: StrokeStyle(lineWidth: 2 * CGFloat(size) / 24, lineCap: .round)
                            )
                            .frame(width: CGFloat(size), height: CGFloat(size))
                    }
                }
            }
        }
    }
}
#endif
