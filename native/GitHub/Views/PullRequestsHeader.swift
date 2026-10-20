import GitHub
import SwiftUI

/// The list's title row and controls: refresh with the time of the last update, then scope tabs,
/// a search field and the grouping and drafts options.
struct PullRequestsHeader: View {
    /// Space on each side, so the header's edges line up with the list's.
    let sideInset: CGFloat

    @Environment(GitHubModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                Text("Pull Requests")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                Spacer(minLength: DS.Space.md)
                if let inbox = model.inbox {
                    TimelineView(.everyMinute) { _ in
                        Text("Updated \(inbox.fetchedAt, format: .relative(presentation: .named))")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                if model.isRefreshing {
                    DotGridLoader(pattern: .waiting)
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                        .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                        .accessibilityLabel("Refreshing")
                } else {
                    IconButton("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                }
            }

            // Filters only mean something once there's a list to filter.
            if let inbox = model.inbox, !inbox.all.isEmpty {
                HStack(spacing: DS.Space.md) {
                    PullRequestScopeTabs(scope: $model.filter.scope, inbox: model.inbox)
                    Spacer(minLength: DS.Space.md)
                    SearchField("Filter pull requests", text: $model.filter.query)
                        .frame(width: DS.Size.sidebarWidth - DS.Space.xxxl)
                    optionsMenu
                }
            }
        }
        .padding(.horizontal, sideInset + DS.Space.md)
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.lg)
    }

    private var optionsMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Group By", selection: $model.filter.grouping) {
                Text("Involvement").tag(PullRequestFilter.Grouping.involvement)
                Text("Repository").tag(PullRequestFilter.Grouping.repository)
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Show Drafts", isOn: $model.filter.includesDrafts)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: DS.Size.navIcon))
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(
            model.filter.grouping == .repository || !model.filter.includesDrafts ? .dsTextPrimary : .dsTextSecondary
        )
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(model.filter.grouping == .repository || !model.filter.includesDrafts ? .dsSelected : .clear)
        }
        .help("Group and Filter")
        .accessibilityLabel("Group and Filter")
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pull requests header") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xxl) {
            PullRequestsHeader(sideInset: DS.Space.xl)
                .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
            // No list yet: just the title and refresh.
            PullRequestsHeader(sideInset: DS.Space.xl)
                .environment(GitHubModel.preview())
        }
        .frame(width: 900)
    }
}
#endif
