import SwiftUI

/// Quiet focus: the project's name set large, right on top of the composer, with one exact line of
/// where the task works, the changes that stay behind if they matter, and what the keyboard does.
/// Everything sits on the composer's left edge, so the name, the line and the composer read as one
/// block and the empty space above them stays empty.
struct NewSessionFocusView: View {
    let context: NewSessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.lg) {
                if !context.projectIcon.isInitial {
                    ProjectAvatar(
                        name: context.projectName, icon: context.projectIcon, size: NewSessionMetrics.titleIcon)
                }
                Text(context.projectName)
                    .font(.ds(NewSessionMetrics.titleSize, weight: .semibold))
                    .tracking(NewSessionMetrics.titleTracking)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(NewSessionMetrics.titleMinimumScale)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                NewSessionWorkspaceLine(workspace: context.workspace, projectName: context.projectName)
                NewSessionChangesNote(
                    count: context.checkoutChanges, workspace: context.workspace, projectName: context.projectName,
                    font: .dsCallout)
            }
            .padding(.top, DS.Space.sm)
            SeparatorLine()
                .padding(.top, DS.Space.xl)
                .padding(.bottom, DS.Space.lg)
            NewSessionKeyHints(keys: context.keys, lastAction: context.actions.first(where: \.isLast)?.name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ProjectIcon {
    /// Just the name's first letter, which the large name already says.
    var isInitial: Bool {
        if case .initial = self { true } else { false }
    }
}
