import SwiftUI

/// Marks the run of a source line a diagnostic points at, for `DiagnosticSquiggleRenderer`.
struct DiagnosticSquiggle: TextAttribute {}

/// Draws text as usual, with a wavy rule under the runs marked `DiagnosticSquiggle`: the mark a
/// compiler puts under the part of a line it couldn't read.
struct DiagnosticSquiggleRenderer: TextRenderer {
    let color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)
                guard run[DiagnosticSquiggle.self] != nil else { continue }
                let bounds = run.typographicBounds
                let y = bounds.origin.y + DS.Approval.squiggleOffset
                context.stroke(
                    wave(from: bounds.rect.minX, to: bounds.rect.maxX, at: y), with: .color(color),
                    lineWidth: DS.Approval.rule)
            }
        }
    }

    private func wave(from start: CGFloat, to end: CGFloat, at y: CGFloat) -> Path {
        Path { path in
            let half = DS.Approval.squiggleWavelength / 2
            var x = start
            var up = true
            path.move(to: CGPoint(x: x, y: y))
            while x < end {
                let next = min(x + half, end)
                let peak = y + (up ? -DS.Approval.squiggleAmplitude : DS.Approval.squiggleAmplitude)
                path.addQuadCurve(to: CGPoint(x: next, y: y), control: CGPoint(x: (x + next) / 2, y: peak))
                x = next
                up.toggle()
            }
        }
    }
}
