import SwiftUI

/// A bubble: round corners away from the speaker, tighter ones where bubbles of a group meet, and
/// a small hooked tail at the bottom of the group's last bubble. The tail lives in a strip of
/// `BubbleMetrics.tailWidth` on the speaker's side that every bubble reserves.
nonisolated struct BubbleShape: Shape {
    var side: BubbleSide
    var position: BubbleGroupPosition

    func path(in rect: CGRect) -> Path {
        // Drawn for the user's side (tail on the right), then mirrored for the agent's.
        let path = trailingPath(in: rect)
        guard side == .leading else { return path }
        return path.applying(CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0).scaledBy(x: -1, y: 1))
    }

    private func trailingPath(in rect: CGRect) -> Path {
        let tail = BubbleMetrics.tailWidth
        let body = CGRect(x: rect.minX, y: rect.minY, width: max(rect.width - tail, 0), height: rect.height)
        let radius = min(BubbleMetrics.radius, body.height / 2, body.width / 2)
        let tight = min(BubbleMetrics.groupedRadius, radius)
        let topSide = position.isFirst ? radius : tight
        let bottomSide = position.isLast ? radius : tight

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY),
            radius: topSide
        )
        if position.isLast {
            // Down the side, then flare out into the tip and sweep back under the bubble.
            let tip = CGPoint(x: rect.maxX, y: body.maxY)
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
            path.addCurve(
                to: tip,
                control1: CGPoint(x: body.maxX, y: body.maxY - radius * 0.35),
                control2: CGPoint(x: body.maxX + tail * 0.4, y: body.maxY - tail * 0.15)
            )
            path.addCurve(
                to: CGPoint(x: body.maxX - radius * 0.9, y: body.maxY),
                control1: CGPoint(x: rect.maxX - tail * 1.4, y: body.maxY + tail * 0.05),
                control2: CGPoint(x: body.maxX - radius * 0.4, y: body.maxY - tail * 0.2)
            )
        } else {
            path.addArc(
                tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY),
                radius: bottomSide
            )
        }
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}
