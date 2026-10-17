import SwiftUI

/// The startup animation: Native's emblem assembling itself at the center of an empty window, in
/// the spirit of Factory's loading screen (a small line drawing in the primary color on the bare
/// background) but with our own choreography. The two links trace their outlines in from opposite
/// corners, slide together until they interlock, fill in, hold, then unwind and repeat until the
/// caller removes the view. With Reduce Motion it shows the finished emblem.
public struct LaunchAnimationView: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    /// - Parameter size: Width of the emblem.
    public init(size: CGFloat = 100) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Color.dsBackground
            if reduceMotion {
                LaunchEmblem(frame: .assembled, size: size)
            } else {
                TimelineView(.animation) { context in
                    let elapsed = max(context.date.timeIntervalSince(start), 0)
                    let time = elapsed.truncatingRemainder(dividingBy: LaunchFrame.timeline.duration)
                    LaunchEmblem(frame: LaunchFrame.timeline.value(time: time), size: size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Covers the view with the launch animation while `isPresented`, then fades to the content
    /// over 120ms so the swap doesn't flash.
    public func launchScreen(isPresented: Bool) -> some View {
        overlay {
            if isPresented {
                LaunchAnimationView()
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
    }
}

/// The animated values at one moment.
private struct LaunchFrame {
    /// How much of each link's outline is drawn, 0...1.
    var rightTrace: CGFloat = 0
    var leftTrace: CGFloat = 0
    /// How far apart the links are, as a share of the emblem's width (0 interlocks them).
    var separation: CGFloat = 0.1
    /// Opacity of the solid fill over the outlines.
    var fill: Double = 0

    static let assembled = LaunchFrame(rightTrace: 1, leftTrace: 1, separation: 0, fill: 1)

    /// One 2.6s cycle: trace (0.7s), interlock (0.4s), fill (0.3s), hold, unwind.
    static let timeline = KeyframeTimeline(initialValue: LaunchFrame()) {
        KeyframeTrack(\.rightTrace) {
            CubicKeyframe(1, duration: 0.7)
            LinearKeyframe(1, duration: 1.3)
            CubicKeyframe(0, duration: 0.45)
            LinearKeyframe(0, duration: 0.15)
        }
        KeyframeTrack(\.leftTrace) {
            LinearKeyframe(0, duration: 0.12)
            CubicKeyframe(1, duration: 0.7)
            LinearKeyframe(1, duration: 1.18)
            CubicKeyframe(0, duration: 0.45)
            LinearKeyframe(0, duration: 0.15)
        }
        KeyframeTrack(\.separation) {
            LinearKeyframe(0.1, duration: 0.6)
            SpringKeyframe(0, duration: 0.5, spring: .snappy)
            LinearKeyframe(0, duration: 0.9)
            CubicKeyframe(0.1, duration: 0.45)
            LinearKeyframe(0.1, duration: 0.15)
        }
        KeyframeTrack(\.fill) {
            LinearKeyframe(0, duration: 1.0)
            CubicKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 0.7)
            CubicKeyframe(0, duration: 0.2)
            LinearKeyframe(0, duration: 0.4)
        }
    }
}

/// The emblem at one frame: each link's outline traced as far as the frame says, offset along the
/// diagonal it slides in on, with the fill fading in over the outlines.
private struct LaunchEmblem: View {
    let frame: LaunchFrame
    let size: CGFloat

    var body: some View {
        let offset = frame.separation * size
        ZStack {
            link(.right, trace: frame.rightTrace)
                .offset(x: offset, y: -offset * 0.6)
            link(.left, trace: frame.leftTrace)
                .offset(x: -offset, y: offset * 0.6)
        }
        .frame(width: size, height: size / NativeMark.aspectRatio)
        .accessibilityHidden(true)
    }

    private func link(_ link: NativeMark.Link, trace: CGFloat) -> some View {
        ZStack {
            NativeMark(link: link)
                .trim(from: 0, to: trace)
                .stroke(
                    .dsTextPrimary, style: StrokeStyle(lineWidth: max(size / 70, 1), lineCap: .round, lineJoin: .round)
                )
                // The outline gives way to the fill, so the finished emblem has the mark's weight.
                .opacity(1 - frame.fill)
            NativeMark(link: link)
                .fill(.dsTextPrimary)
                .opacity(frame.fill)
        }
    }
}

#Preview("Launch") {
    DSPreviewPair {
        LaunchAnimationView()
            .frame(width: 320, height: 220)
    }
}
