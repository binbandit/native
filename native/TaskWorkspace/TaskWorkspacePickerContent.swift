import SwiftUI

struct TaskWorkspacePickerContent: View {
    let options: [TaskWorkspaceOption]
    @Binding var selection: TaskWorkspaceChoice?
    let isLoading: Bool
    let isChanging: Bool
    let error: String?
    let cancel: () -> Void
    let retry: () -> Void
    let apply: () -> Void
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Change Workspace")
                .font(.dsHeadline)
            Text("Choose where this task runs. After its first message, the workspace stays fixed.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if isLoading {
                LoadingStateView("Reading workspaces…")
                    .frame(height: DS.TaskWorkspace.listHeight)
            } else if !options.isEmpty {
                SearchField("Find a branch or worktree", text: $search)
                ScrollView {
                    VStack(spacing: DS.Space.xs) {
                        ForEach(filtered) { option in
                            Button {
                                selection = option.choice
                            } label: {
                                HStack(spacing: DS.Space.md) {
                                    Image(systemName: selection == option.choice ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selection == option.choice ? .dsAccent : .dsTextTertiary)
                                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                        Text(option.title).font(.dsBodyMedium)
                                        Text(option.detail).font(.dsCaption).foregroundStyle(.dsTextSecondary)
                                            .lineLimit(2).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 0)
                                    if option.isCurrent {
                                        Text("Current").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                                    }
                                }
                                .padding(DS.Space.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .background(
                                selection == option.choice ? Color.dsSurfaceSunken : .clear,
                                in: .rect(cornerRadius: DS.Radius.control)
                            )
                            .dsHitTarget(DS.Size.controlMD)
                            .disabled(option.isCurrent || isChanging)
                        }
                        if filtered.isEmpty {
                            Text("No matching branches or worktrees. Try another name.")
                                .font(.dsBody).foregroundStyle(.dsTextSecondary).padding(DS.Space.lg)
                        }
                    }
                }
                .frame(height: DS.TaskWorkspace.listHeight)
            }
            if let error {
                Text(error).font(.dsBody).foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
                if options.isEmpty {
                    Button("Retry", action: retry).buttonStyle(.ds(.secondary, size: .medium))
                }
            }
            if isChanging { LoadingStateView("Changing workspace…") }
            HStack(spacing: DS.Space.md) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .keyboardShortcut(.cancelAction)
                    .disabled(isChanging)
                Button("Use Workspace", action: apply)
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(isLoading || isChanging || selection == nil)
            }
        }
        .padding(DS.Space.xxl)
        .frame(idealWidth: DS.TaskWorkspace.sheetWidth, maxWidth: DS.TaskWorkspace.sheetWidth)
        .background(.dsBackground)
    }

    private var filtered: [TaskWorkspaceOption] {
        options.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.detail.localizedCaseInsensitiveContains(search)
        }
    }
}

#if DEBUG
#Preview("Workspace picker - Branches") {
    DSPreviewPair {
        TaskWorkspacePickerContent(
            options: TaskWorkspacePreviewFixtures.options, selection: .constant(.newWorktree),
            isLoading: false, isChanging: false, error: nil, cancel: {}, retry: {}, apply: {})
    }
}

#Preview("Workspace picker - Failure") {
    DSPreviewPair {
        TaskWorkspacePickerContent(
            options: TaskWorkspacePreviewFixtures.options, selection: .constant(.newWorktree),
            isLoading: false, isChanging: false,
            error: "The branch is no longer available. Choose another workspace. Your draft is kept.",
            cancel: {}, retry: {}, apply: {})
    }
}

#Preview("Workspace picker - Changing") {
    DSPreviewPair {
        TaskWorkspacePickerContent(
            options: TaskWorkspacePreviewFixtures.options, selection: .constant(.project),
            isLoading: false, isChanging: true, error: nil, cancel: {}, retry: {}, apply: {})
    }
}
#endif
