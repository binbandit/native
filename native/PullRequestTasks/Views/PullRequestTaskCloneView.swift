import GitHub
import SwiftUI

/// No project is a checkout of the pull request's repository: where to clone it, with what's in
/// that folder now. Nothing is cloned until the user confirms.
struct PullRequestTaskCloneView: View {
    let missing: PullRequestTaskCheckout.NoProject
    let folder: URL
    /// `nil` while the folder is being looked at.
    let state: PullRequestTaskCheckout.FolderState?
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("None of your projects is a checkout of \(missing.repository.nameWithOwner).")
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
            HStack(spacing: DS.Space.md) {
                Image(systemName: "folder")
                    .foregroundStyle(.dsTextSecondary)
                    .accessibilityHidden(true)
                Text(PullRequestTaskPaths.abbreviated(folder))
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: DS.Space.md)
                Button("Choose…", action: chooseFolder)
                    .buttonStyle(.ds(.secondary))
                    .help("Choose where the repository goes")
            }
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: DS.Size.controlMD)
            .background(.dsSurfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            status
        }
        .padding(DS.Space.xl)
    }

    @ViewBuilder private var status: some View {
        switch state {
        case nil:
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                Text("Checking the folder…")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
            }
        case .free:
            note(
                "Native clones it here with GitHub CLI, adds it as a project, then opens the pull request in a worktree of it."
            )
        case .checkout:
            note("This folder is already a checkout of it. Native adds it as a project, then opens the pull request.")
        case .taken:
            NoticeBanner(
                tone: .warning, title: "Something else is in this folder",
                detail: "Choose an empty folder, or one that's a checkout of \(missing.repository.nameWithOwner).")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
