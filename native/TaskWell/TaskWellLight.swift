import SwiftUI

/// A single outward pass at a turn boundary. No repeating timer or mid-turn light.
struct TaskWellLight: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            Color.clear
                .frame(height: DS.TaskWell.lightHeight)
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { _, progress in
                    GeometryReader { proxy in
                        let width = proxy.size.width * DS.TaskWell.lightWidthShare
                        ForEach([-1, 1], id: \.self) { direction in
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .dsTextPrimary.opacity(DS.TaskWell.lightPeak), .clear],
                                        startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: width, height: DS.TaskWell.lightHeight)
                                .position(
                                    x: proxy.size.width / 2 + CGFloat(direction) * progress * proxy.size.width / 2,
                                    y: DS.TaskWell.lightHeight / 2
                                )
                                .opacity(progress > 0 && progress < 1 ? 1 - progress : 0)
                        }
                    }
                } keyframes: { _ in
                    LinearKeyframe(0, duration: 0)
                    CubicKeyframe(1, duration: DS.TaskWell.lightDuration)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview("Well - Reduced motion light") {
    DSPreviewPair { TaskWellLight(trigger: 0).environment(\.accessibilityReduceMotion, true) }
}

#Preview("Well - One light pass") {
    @Previewable @State var trigger = 0
    DSPreviewPair {
        VStack {
            Button("Start or land a turn") { trigger += 1 }
            TaskWellLight(trigger: trigger)
        }
        .frame(width: DS.TaskWell.width)
        .padding(DS.Space.xl)
    }
}
#endif
