import SwiftUI

/// Placeholder rows while the first load runs.
struct PullRequestListSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            ForEach(0..<2, id: \.self) { section in
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    bar(width: DS.Size.sidebarWidth / 2)
                        .padding(.horizontal, DS.Space.md)
                    ForEach(0..<(section == 0 ? 2 : 4), id: \.self) { row in
                        HStack(alignment: .top, spacing: DS.Space.md) {
                            Circle()
                                .fill(.dsSurfaceSunken)
                                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                            VStack(alignment: .leading, spacing: DS.Space.sm) {
                                bar(width: PullRequestsLayout.contentWidth * (row.isMultiple(of: 2) ? 0.55 : 0.45))
                                bar(width: DS.Size.sidebarWidth)
                            }
                        }
                        .padding(.horizontal, DS.Space.md)
                    }
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: PullRequestsLayout.contentWidth, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Loading pull requests")
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(.dsSurfaceSunken)
            .frame(width: width, height: DS.Space.md + DS.Space.xxs)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pull request list loading") {
    DSPreviewPair {
        PullRequestListSkeleton()
            .frame(width: PullRequestsLayout.contentWidth)
    }
}
#endif
