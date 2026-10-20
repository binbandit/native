import SwiftUI

/// A notice under the inspector's header or in the commit form: what happened, what to do, git's
/// own words when they help, and the one next step.
struct GitNoticeBanner: View {
    let notice: GitNotice
    let onAction: (GitNotice.Action) -> Void
    /// `nil` for notices that last as long as their cause, like unresolved conflicts.
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image(systemName: notice.tone == .failure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.tone == .failure ? Color.dsDanger : .dsSuccess)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(notice.title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let message = notice.message {
                    Text(message)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                if let detail = notice.detail {
                    CappedHeightScrollView(maxHeight: GitMetrics.noticeDetailMaxHeight) {
                        Text(detail)
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.sm)
                    }
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                }
                if let action = notice.action {
                    Button(action.title) { onAction(action) }
                        .buttonStyle(.ds(.secondary))
                        .padding(.top, DS.Space.xxs)
                }
            }
            .tracking(DS.Tracking.tight)
            // No vertical fixedSize: inside the inspector's split view it makes the column's minimum
            // height that of the text wrapped at zero width, which grows the window without end.
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
                    .dsHitTarget(DS.Size.controlXS)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.Space.xs }
            }
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.md)
        .background(notice.tone == .failure ? Color.dsDanger.opacity(0.06) : .dsSuccess.opacity(0.06))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Notices") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            GitNoticeBanner(notice: GitPreviewFixtures.pushRejected, onAction: { _ in }, onDismiss: {})
            GitNoticeBanner(notice: GitPreviewFixtures.committed, onAction: { _ in }, onDismiss: {})
            // Lasts as long as its cause, so it can't be dismissed.
            GitNoticeBanner(
                notice: GitNotice(
                    tone: .failure, title: "2 files have conflicts",
                    message: "Resolve them, then stage the files to finish the merge.", action: .showConflicts),
                onAction: { _ in })
        }
        .frame(width: GitMetrics.inspectorIdealWidth)
    }
}
#endif
