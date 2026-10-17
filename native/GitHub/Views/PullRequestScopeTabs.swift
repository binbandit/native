import GitHub
import SwiftUI

/// All / Mine / Review requested / Assigned, with counts (Conductor's create-from tabs: 24pt
/// ghost buttons, the active one filled).
struct PullRequestScopeTabs: View {
    @Binding var scope: PullRequestFilter.Scope
    let inbox: PullRequestInbox?

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(PullRequestFilter.Scope.allCases, id: \.self) { tab in
                ScopeTab(title: title(tab), count: count(tab), isSelected: scope == tab) {
                    scope = tab
                }
            }
        }
    }

    private func title(_ scope: PullRequestFilter.Scope) -> String {
        switch scope {
        case .all: "All"
        case .authored: "Mine"
        case .reviewRequested: "Review requested"
        case .assigned: "Assigned"
        }
    }

    private func count(_ scope: PullRequestFilter.Scope) -> Int? {
        guard let inbox else { return nil }
        return switch scope {
        case .all: inbox.all.count
        case .authored: inbox.authored.count
        case .reviewRequested: inbox.reviewRequested.count
        case .assigned: inbox.assigned.count
        }
    }
}

private struct ScopeTab: View {
    let title: String
    let count: Int?
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
                    Text("\(count)")
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
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
