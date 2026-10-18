import GitHub
import SwiftUI

/// Conversation, Files Changed and Checks, with their counts (the reference app's right panel tabs: ghost
/// buttons, the active one filled).
struct PullRequestPageTabBar: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(PullRequestPageModel.Tab.allCases) { tab in
                PullRequestPageTab(title: tab.title, count: count(tab), isSelected: model.tab == tab) {
                    model.tab = tab
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
    }

    private func count(_ tab: PullRequestPageModel.Tab) -> String? {
        switch tab {
        case .conversation:
            let comments = page.timeline.filter { if case .comment = $0 { true } else { false } }.count
            return comments + page.threadsTotal > 0 ? "\(comments + page.threadsTotal)" : nil
        case .files:
            return "\(page.changedFiles)"
        case .checks:
            return page.checks.map { "\($0.total)" }
        }
    }
}

private struct PullRequestPageTab: View {
    let title: String
    let count: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Text(title)
                    .font(.dsBody)
                    .tracking(DS.Tracking.tight)
                if let count {
                    Text(count)
                        .font(.dsMonoMicro)
                        .foregroundStyle(isSelected ? .dsTextSecondary : .dsTextTertiary)
                }
            }
            .foregroundStyle(isSelected || isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.md + DS.Space.xxs)
            .frame(height: DS.Size.controlXS)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
            }
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
