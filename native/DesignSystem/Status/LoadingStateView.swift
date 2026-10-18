import SwiftUI

/// The one loading state for a pane: the dot-grid loader and what's on its way, centered. Never an
/// ad-hoc spinner.
public struct LoadingStateView: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        VStack(spacing: DS.Space.md) {
            DotGridLoader(pattern: .settingUp)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
            Text(title)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        }
        .tracking(DS.Tracking.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Loading state") {
    DSPreviewPair {
        LoadingStateView("Loading session…")
    }
}
