import GitHub
import SwiftUI

/// A titled, collapsible run of pull requests (the reference app `PullRequestListSection`): the title and
/// count toggle it, and the chevron only shows on hover while expanded.
struct PullRequestGroupSection: View {
    let group: PullRequestGroup
    @Binding var isCollapsed: Bool
    /// Off when the group is a repository, which its title already names.
    var showsRepository = true

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Button {
                withAnimation(.dsDisclosure) { isCollapsed.toggle() }
            } label: {
                HStack(spacing: DS.Space.md) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                        Text(title)
                            .font(.dsBodyMedium)
                            .foregroundStyle(.dsTextPrimary)
                            .lineLimit(1)
                        Text("\(group.pullRequests.count)")
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: DS.Size.navIcon - DS.Space.xs, weight: .semibold))
                        .foregroundStyle(.dsTextTertiary)
                        .opacity(isCollapsed || isHovered ? 1 : 0)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: DS.Size.controlXS)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .trackHover($isHovered)
            .accessibilityLabel(title)
            .accessibilityValue("\(group.pullRequests.count) pull requests, \(isCollapsed ? "collapsed" : "expanded")")
            .accessibilityAddTraits(.isHeader)

            if !isCollapsed {
                if group.pullRequests.isEmpty {
                    Text(emptyMessage)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(group.pullRequests) { pullRequest in
                            PullRequestRow(pullRequest: pullRequest, showsRepository: showsRepository)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var title: String {
        switch group.id {
        case .involvement(.reviewRequested): "Review requested"
        case .involvement(.author): "Mine"
        case .involvement(.assignee): "Assigned to me"
        case .repository(let repository): repository
        }
    }

    private var emptyMessage: String {
        switch group.id {
        case .involvement(.reviewRequested): "Nothing is waiting on your review."
        case .involvement(.author): "You have no open pull requests."
        case .involvement(.assignee): "Nothing is assigned to you."
        case .repository: "No pull requests."
        }
    }
}
