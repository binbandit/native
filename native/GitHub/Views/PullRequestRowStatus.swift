import SwiftUI

/// One line under a row saying what an action from the list is doing: a loader while it works, a
/// check when it's done, and the reason (in GitHub's words) when it failed, until dismissed.
struct PullRequestRowStatus: View {
    let activity: PullRequestRowActivity
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            switch activity {
            case .working(let text):
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                Text(text)
                    .foregroundStyle(.dsTextSecondary)
            case .done(let text):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.dsSuccess)
                Text(text)
                    .foregroundStyle(.dsTextSecondary)
            case .failed(let text):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.dsDanger)
                Text(text)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Space.md)
                IconButton("Dismiss", systemImage: "xmark", action: dismiss)
            }
        }
        .font(.dsCaption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Row status") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            PullRequestRowStatus(activity: .working("Merging…"), dismiss: {})
            PullRequestRowStatus(activity: .done("Merged into main"), dismiss: {})
            PullRequestRowStatus(
                activity: .failed("Couldn’t merge #974: required status check “test” is failing."), dismiss: {})
        }
        .frame(width: PullRequestsLayout.contentWidth)
    }
}
#endif
