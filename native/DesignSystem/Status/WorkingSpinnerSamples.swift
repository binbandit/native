import AppAppearance
import SwiftUI

/// Same-size, neutral samples shared by Appearance and the Gallery.
struct WorkingSpinnerSamples: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: DS.Space.lg) {
            ForEach(WorkingAnimation.allCases, id: \.self) { animation in
                VStack(spacing: DS.Space.sm) {
                    DotGridLoader(pattern: .working(animation))
                        .frame(width: DS.Size.statusGlyph * 2, height: DS.Size.statusGlyph * 2)
                    Text(animation.title)
                        .font(.dsCaption)
                }
            }
        }
        .foregroundStyle(.dsTextSecondary)
    }
}

#if DEBUG
#Preview("Working spinners - All animations") {
    DSPreviewPair {
        WorkingSpinnerSamples().frame(width: 600)
    }
}

#Preview("Working spinners - Reduce Motion") {
    DSPreviewPair {
        WorkingSpinnerSamples().frame(width: 600)
            .environment(\.accessibilityReduceMotion, true)
    }
}
#endif
