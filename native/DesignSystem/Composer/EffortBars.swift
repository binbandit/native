import SwiftUI

/// the reference app's level meter (`ReasoningLevelBars`): 6x11pt bars 2pt apart, lit in the accent up to the
/// current level, e.g. reasoning effort or autonomy. Muted bars mean the level isn't set and the
/// agent picks it. `tint` recolors the lit bars, e.g. `.dsDanger` so full access stands out.
public struct EffortBars: View {
    let total: Int
    let level: Int
    let isMuted: Bool
    let tint: Color

    public init(total: Int = 3, level: Int, isMuted: Bool = false, tint: Color = .dsAccent) {
        self.total = total
        self.level = level
        self.isMuted = isMuted
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isMuted ? .dsTextQuaternary : index < level ? tint : .dsBorder)
                    .frame(width: 6, height: 11)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue(isMuted ? "Automatic" : "\(level) of \(total)")
    }
}

#Preview("Effort bars") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            EffortBars(level: 0)
            EffortBars(level: 2)
            EffortBars(total: 4, level: 4)
            EffortBars(level: 1, isMuted: true)
            EffortBars(total: 4, level: 4, tint: .dsDanger)
        }
    }
}
