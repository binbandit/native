import SwiftUI

/// Minute updates confined to the content that needs them, using the app's shared, visibility-aware
/// clock. Keep this around the age or countdown so a tick doesn't rebuild the surrounding screen.
public struct DSMinuteTimeline<Content: View>: View {
    private let content: (Date) -> Content

    public init(@ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(DSMinuteClock.shared.now)
    }
}

#Preview("Minute timeline") {
    let date = Date.now.addingTimeInterval(-300)
    DSPreviewPair {
        DSMinuteTimeline { now in
            Text(DSFormat.compactAge(date, now: now))
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }
}
