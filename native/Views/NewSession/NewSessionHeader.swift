import SwiftUI

/// The top of a new session: the project's name in display type, after its own icon when it has
/// one, then exactly where the task works and the project's uncommitted changes when they matter.
/// The name moves out by the extra bearing display type has, so its first letter's ink lines up with
/// the smaller text below it and with the composer's.
struct NewSessionHeader: View {
    let context: NewSessionContext
    @State private var isChangingFolder = false
    @State private var folderFailure: String?

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
                if let choose = context.chooseWorkspace {
                    TaskFolderChoice(
                        location: isProjectFolder ? .project : .separate, sharedFolderNote: context.sharedFolderNote,
                        isChanging: isChangingFolder,
                        choose: { choice in
                            isChangingFolder = true
                            folderFailure = nil
                            Task {
                                defer { isChangingFolder = false }
                                do { try await choose(choice) } catch { folderFailure = error.localizedDescription }
                            }
                        }, more: context.changeWorkspace)
                } else if let changeWorkspace = context.changeWorkspace {
                    Button("Change Workspace…", action: changeWorkspace).buttonStyle(.plain).font(.dsCallout)
                }
                if let folderFailure {
                    Text(folderFailure).font(.dsCallout).foregroundStyle(.dsDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NewSessionChangesNote(
                    count: context.checkoutChanges, workspace: context.workspace, projectName: context.projectName)
                if let device = context.device {
                    NewSessionDeviceLine(device: device, projectName: context.projectName)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var isProjectFolder: Bool {
        if case .checkout = context.workspace { return true }
        return context.workspace.isPlainFolder
    }
}

#if DEBUG
#Preview("New task - Choose workspace") {
    DSPreviewPair {
        NewSessionHeader(context: TaskWorkspacePreviewFixtures.context(editable: true))
            .padding(DS.Space.xxl)
            .frame(width: DS.Size.popoverWidth)
    }
}

#Preview("New task - Shared project folder") {
    DSPreviewPair {
        let context = NewSessionContext(
            projectName: "Sample", projectIcon: .initial, workspace: .checkout(branch: "main"),
            checkoutChanges: 1, tasks: [], pullRequests: [], actions: [], draft: { _ in }, editActions: {},
            chooseWorkspace: { _ in },
            sharedFolderNote: "Another running task uses this folder. You would edit the same files.")
        NewSessionHeader(context: context).padding(DS.Space.xxl).frame(width: DS.TaskWorkspace.sheetWidth)
    }
}

#Preview("New task - Workspace locked") {
    DSPreviewPair {
        NewSessionHeader(context: TaskWorkspacePreviewFixtures.context(editable: false))
            .padding(DS.Space.xxl)
            .frame(width: DS.Size.popoverWidth)
    }
}
#endif

extension ProjectIcon {
    /// Just the name's first letter, which the large name already says.
    var isInitial: Bool {
        if case .initial = self { true } else { false }
    }
}
