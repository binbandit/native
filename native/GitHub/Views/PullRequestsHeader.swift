import GitHub
import SwiftUI

/// The list's title row and controls: refresh with the time of the last update, then scope tabs,
/// a search field and the grouping and drafts options.
struct PullRequestsHeader: View {
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
                IconButton("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh(rereadEnvironment: model.availability != nil && model.inbox == nil) }
                }
                .disabled(model.isRefreshing)
            }

            HStack(spacing: DS.Space.md) {
                PullRequestScopeTabs(scope: $model.filter.scope, inbox: model.inbox)
                Spacer(minLength: DS.Space.md)
                PullRequestSearchField(query: $model.filter.query)
                optionsMenu
            }
        }
        .padding(.horizontal, DS.Space.xl + DS.Space.md)
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.lg)
        .frame(maxWidth: PullRequestsLayout.contentWidth)
        .frame(maxWidth: .infinity)
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
        .foregroundStyle(model.filter.grouping == .repository || !model.filter.includesDrafts ? .dsTextPrimary : .dsTextSecondary)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(model.filter.grouping == .repository || !model.filter.includesDrafts ? .dsSelected : .clear)
        }
        .help("Group and Filter")
        .accessibilityLabel("Group and Filter")
    }
}
