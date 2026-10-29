import SwiftUI

/// The two common starting places stay beside the task's other options.
struct TaskFolderChoice: View {
    enum Location {
        case project, newBranch, separate

        var label: String {
            switch self {
            case .project: "Project folder"
            case .newBranch: "New branch"
            case .separate: "Separate folder"
            }
        }
    }

    let location: Location
    private var isProjectFolder: Bool { location == .project }
    var sharedFolderNote: String?
    var isChanging = false
    var canCreateSeparateFolder = true
    let choose: (TaskWorkspaceChoice) -> Void
    var more: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Menu {
                Button {
                    choose(.newWorktree)
                } label: {
                    Label(
                        "New branch in a separate folder",
                        systemImage: location == .newBranch ? "checkmark" : "arrow.triangle.branch")
                }
                .disabled(!canCreateSeparateFolder)
                Button {
                    choose(.project)
                } label: {
                    Label("Project folder on its current branch", systemImage: isProjectFolder ? "checkmark" : "folder")
                }
                if let more {
                    Divider()
                    Button("More folders and branches…", action: more)
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: isProjectFolder ? "folder" : "arrow.triangle.branch")
                    Text(isChanging ? "Changing folder…" : location.label)
                    Image(systemName: "chevron.down").font(.dsMicro)
                }
                .font(.dsCallout)
                .foregroundStyle(.dsTextSecondary)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .dsHitTarget(DS.Size.controlMD)
            .disabled(isChanging)
            .accessibilityLabel("Task folder")
            .accessibilityValue(location.label)
            if isProjectFolder, let sharedFolderNote {
                Text(sharedFolderNote).font(.dsCallout).foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
#Preview("Task folder - Separate, project and shared") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            TaskFolderChoice(location: .newBranch, choose: { _ in })
            TaskFolderChoice(location: .project, choose: { _ in })
            TaskFolderChoice(location: .project, canCreateSeparateFolder: false, choose: { _ in })
            TaskFolderChoice(
                location: .project,
                sharedFolderNote: "Another running task uses this folder. You would edit the same files.",
                choose: { _ in })
        }.padding(DS.Space.xxl).frame(width: DS.TaskWorkspace.sheetWidth)
    }
}
#endif
