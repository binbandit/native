import SwiftUI

/// What the push would drop, under the command: the newest few commits only the remote has.
struct ApprovalPushDrops: View {
    let reach: ApprovalPushReach
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Would be dropped from \(reach.branch ?? "the branch") on \(reach.place)")
                .font(.dsCaption).foregroundStyle(.dsTextTertiary)
            Text("From this clone's last fetch")
                .font(.dsCaption).foregroundStyle(.dsTextTertiary)
            ForEach(reach.dropped) { commit in
                HStack(spacing: DS.Approval.fixItGap) {
                    Text(commit.hash).font(.dsMonoCaption).foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Approval.commitHashWidth, alignment: .leading)
                    DSInlineCodeText(commit.subject).font(.dsBody).foregroundStyle(.dsTextPrimary)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    DSMinuteTimeline { now in
                        Text(DSFormat.compactAge(commit.date, now: now) + " ago")
                    }
                    .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                }
                .frame(minHeight: DS.Approval.commitRowHeight)
            }
            if let ahead = reach.ahead, ahead > reach.dropped.count {
                Text("and \(ahead - reach.dropped.count) more").font(.dsCaption).foregroundStyle(.dsTextTertiary)
            }
        }
        .padding(.horizontal, DS.Approval.commandInset)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Approval - Commits a force-push would drop") {
    DSPreviewPair {
        ApprovalPushDrops(reach: ApprovalPreviewFixtures.forceReach).frame(width: DS.Peek.width)
    }
}
#endif
