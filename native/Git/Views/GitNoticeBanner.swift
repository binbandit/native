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
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
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
