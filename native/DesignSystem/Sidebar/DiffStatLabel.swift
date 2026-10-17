import SwiftUI

/// `+12 −3` in mono, green and red (the reference app `DiffStat`; counts from `DSFormat.lineCount`).
public struct DiffStatLabel: View {
    let added: Int
    let removed: Int
    let isMuted: Bool

    /// - Parameter isMuted: Grays both sides, as the reference app does for unselected rows unless colored
    ///   diffs are on.
    public init(added: Int, removed: Int, isMuted: Bool = false) {
        self.added = added
        self.removed = removed
        self.isMuted = isMuted
    }

    public var body: some View {
        HStack(spacing: DS.Space.xs) {
            if added > 0 {
                Text("+\(DSFormat.lineCount(added))")
                    .foregroundStyle(isMuted ? .dsTextTertiary : .dsSuccess)
            }
            if removed > 0 {
                Text("\u{2212}\(DSFormat.lineCount(removed))")
                    .foregroundStyle(isMuted ? .dsTextTertiary : .dsDanger)
            }
        }
        .font(.ds(10, weight: .medium, design: .mono))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(added) lines added, \(removed) removed")
    }
}

#Preview("Diff stat") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DiffStatLabel(added: 12, removed: 3)
            DiffStatLabel(added: 1280, removed: 0)
            DiffStatLabel(added: 9, removed: 3, isMuted: true)
        }
    }
}
