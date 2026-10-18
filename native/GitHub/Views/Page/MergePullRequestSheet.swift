import GitHub
import SwiftUI

/// Merging, confirmed: how (the methods the repository allows), whether to delete the branch, and
/// what GitHub says about it right now. Merges the commit the page shows, so a push in between
/// fails instead of merging unseen code. Only offered to accounts with push access.
struct MergePullRequestSheet: View {
    let model: PullRequestPageModel

    @Environment(\.dismiss) private var dismiss
    @State private var method: MergeMethod?
    @State private var deletesBranch = true

    var body: some View {
        if let page = model.page {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Merge \(page.reference.display)")
                        .font(.dsHeadline)
                        .foregroundStyle(.dsTextPrimary)
                    Spacer()
                    IconButton("Close", systemImage: "xmark") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.leading, DS.Space.xl)
                .padding(.trailing, DS.Space.md)
                .frame(height: DS.Window.headerHeight + DS.Space.md)
                SeparatorLine()
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    HStack(spacing: DS.Space.xs) {
                        BranchChip(name: page.headRefName)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.dsTextTertiary)
                        BranchChip(name: page.baseRefName)
                    }
                    if let warning = warning(page) {
                        NoticeBanner(tone: .warning, title: warning) { EmptyView() }
                    }
                    Picker(
                        "Merge method", selection: Binding(get: { method ?? defaultMethod(page) }, set: { method = $0 })
                    ) {
                        ForEach(page.mergeMethods, id: \.self) { method in
                            Text(title(method)).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(page.mergeMethods.count < 2)
                    GitHubCheckbox(title: "Delete \(page.headRefName) on GitHub after merging", isOn: $deletesBranch)
                    if let error = model.actionError {
                        Text(error.localizedDescription)
                            .font(.dsBody)
                            .foregroundStyle(.dsDanger)
                    }
                }
                .padding(DS.Space.xl)
                SeparatorLine()
                HStack(spacing: DS.Space.md) {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.ds(.ghost, size: .medium))
                    Button(model.busy.contains("merge") ? "Merging…" : "Merge Pull Request") {
                        Task {
                            if await model.merge(method ?? defaultMethod(page), deleteBranch: deletesBranch) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(
                        page.mergeMethods.isEmpty || model.busy.contains("merge") || page.mergeable == .conflicting)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.vertical, DS.Space.lg)
            }
            .frame(width: CreatePullRequestLayout.width)
            .background(.dsBackground)
            .onAppear { model.actionError = nil }
        }
    }

    private func defaultMethod(_ page: PullRequestPage) -> MergeMethod {
        page.defaultMergeMethod.flatMap { page.mergeMethods.contains($0) ? $0 : nil } ?? page.mergeMethods.first
            ?? .merge
    }

    /// What GitHub says stands in the way, before the user tries.
    private func warning(_ page: PullRequestPage) -> String? {
        if page.mergeable == .conflicting {
            return "This branch has conflicts with \(page.baseRefName). Resolve them first."
        }
        switch page.mergeStatus {
        case .blocked:
            return page.viewerCanMergeAsAdmin
                ? "Branch protection blocks this merge; as an admin, GitHub may let you merge anyway."
                : "Branch protection blocks this merge: it needs approvals or passing required checks."
        case .behind: return "This branch is behind \(page.baseRefName), which must be up to date first."
        case .unstable: return "Some checks failed. They aren't required, so it can still merge."
        default: return page.mergeMethods.isEmpty ? "The repository allows no merge method." : nil
        }
    }

    private func title(_ method: MergeMethod) -> String {
        switch method {
        case .merge: "Merge Commit"
        case .squash: "Squash"
        case .rebase: "Rebase"
        }
    }
}
