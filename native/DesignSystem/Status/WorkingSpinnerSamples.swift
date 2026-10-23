import AppAppearance
import SwiftUI

/// Same-size, neutral samples shared by Appearance and the Gallery.
public struct WorkingSpinnerSamples: View {
    public init() {}

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: DS.Space.lg) {
            ForEach(WorkingAnimation.allCases, id: \.self) { animation in
                sample(animation.title, pattern: .working(animation))
            }
            sample("Reduce Motion", pattern: .typing)
                .environment(\.accessibilityReduceMotion, true)
        }
        .foregroundStyle(.dsTextSecondary)
    }

    private func sample(_ title: String, pattern: DotGridLoader.Pattern) -> some View {
        VStack(spacing: DS.Space.sm) {
            DotGridLoader(pattern: pattern)
                .frame(width: DS.Size.statusGlyph * 2, height: DS.Size.statusGlyph * 2)
            Text(title).font(.dsCaption)
        }
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
