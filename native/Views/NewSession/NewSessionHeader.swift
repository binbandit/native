import SwiftUI

/// The top of a new session: the project's name in display type, after its own icon when it has
/// one, then exactly where the task works and the project's uncommitted changes when they matter.
/// The name moves out by the extra bearing display type has, so its first letter's ink lines up with
/// the smaller text below it and with the composer's.
struct NewSessionHeader: View {
    let context: NewSessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.lg) {
                if !context.projectIcon.isInitial {
                    ProjectAvatar(
                        name: context.projectName, icon: context.projectIcon, size: NewSessionMetrics.titleIcon)
                }
                Text(context.projectName)
                    .font(.dsDisplay)
                    .tracking(DS.Tracking.display)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(NewSessionMetrics.titleMinimumScale)
                    .padding(
                        .leading,
                        context.projectIcon.isInitial ? -DSTypography.displayIndent(of: context.projectName) : 0
                    )
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                NewSessionWorkspaceLine(workspace: context.workspace, projectName: context.projectName)
                NewSessionChangesNote(
                    count: context.checkoutChanges, workspace: context.workspace, projectName: context.projectName)
                if let device = context.device {
                    NewSessionDeviceLine(device: device, projectName: context.projectName)
                }
            }
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
