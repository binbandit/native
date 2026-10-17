import SwiftUI

/// `+12 -3` in mono, green and red (the reference app `DiffStat` with compact counts).
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
                Text("+\(Self.compact(added))")
                    .foregroundStyle(isMuted ? .dsTextTertiary : .dsSuccess)
            }
            if removed > 0 {
                Text("-\(Self.compact(removed))")
                    .foregroundStyle(isMuted ? .dsTextTertiary : .dsDanger)
            }
        }
        .font(.ds(10, weight: .medium, design: .mono))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(added) lines added, \(removed) removed")
    }

    /// `1.2k`, `12k`; the reference app caps the compact form at "✱✱".
    nonisolated static func compact(_ count: Int) -> String {
        if count > 99_000 { return "✱✱" }
        if count >= 10_000 { return "\(Int((Double(count) / 1000).rounded()))k" }
        if count > 999 {
            let thousands = (Double(count) / 100).rounded() / 10
            return thousands == thousands.rounded() ? "\(Int(thousands))k" : "\(thousands)k"
        }
        return "\(count)"
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
