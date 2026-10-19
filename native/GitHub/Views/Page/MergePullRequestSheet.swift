import GitHub
import SwiftUI

/// Merging, confirmed, the way the base branch merges: "Merge When Ready" for a merge queue or
/// auto-merge, or exactly how it merges now ("Squash and Merge into main"), with a sentence saying
/// what clicking does. A merge already arranged shows where it stands and how to take it back.
/// Opened from the page or a row of the list, so it loads the pull request itself and says plainly
/// why it can't merge when it can't. An admin's merge that skips the queue or requirements sits
/// apart and asks first.
struct MergePullRequestSheet: View {
    let model: PullRequestPageModel

    @Environment(\.dismiss) private var dismiss
    @State private var method: MergeMethod?
    @State private var deletesBranch = true
    @State private var isConfirmingAdminMerge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Merge \(model.reference.display)")
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
            if let page = model.page {
                content(page, plan: PullRequestMergePlan(page: page, method: method))
            } else if let error = model.loadError, !model.isLoading {
                NoticeBanner(tone: .danger, title: "Couldn't load the pull request", detail: error.localizedDescription)
                {
                    Button("Try Again") { Task { await model.load() } }
                        .buttonStyle(.ds(.secondary))
                }
                .padding(DS.Space.xl)
            } else {
                HStack(spacing: DS.Space.sm) {
                    DotGridLoader(pattern: .waiting)
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    Text("Checking how it can merge…")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                .padding(DS.Space.xl)
            }
        }
        .frame(width: CreatePullRequestLayout.width)
        .background(.dsBackground)
        .onAppear { model.actionError = nil }
    }

    @ViewBuilder private func content(_ page: PullRequestPage, plan: PullRequestMergePlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.xs) {
                BranchChip(name: page.headRefName)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.dsTextTertiary)
                BranchChip(name: page.baseRefName)
            }
            PullRequestPageStatusLine(page: page, compact: true)
            if let state = plan.state {
                arranged(state, plan: plan)
            } else if let blocker = plan.blocker {
                NoticeBanner(tone: .danger, title: blocker) { EmptyView() }
            } else {
                if let reason = plan.removedFromQueue {
                    NoticeBanner(tone: .warning, title: "Removed from the merge queue: \(reason)") { EmptyView() }
                }
                if let note = plan.note {
                    NoticeBanner(tone: .warning, title: note) { EmptyView() }
                }
                options(page, plan: plan)
            }
            if let error = model.actionError {
                Text(error.localizedDescription)
                    .font(.dsBody)
                    .foregroundStyle(.dsDanger)
                    .textSelection(.enabled)
            }
        }
        .padding(DS.Space.xl)
        SeparatorLine()
        footer(plan)
    }

    /// Queued or set to auto-merge: where it stands, and taking it back.
    private func arranged(_ state: PullRequestMergeState, plan: PullRequestMergePlan) -> some View {
        let isQueued: Bool = if case .queued = state { true } else { false }
        return NoticeBanner(
            tone: .info, systemImage: isQueued ? "list.number" : "clock.arrow.circlepath", title: state.summary,
            detail: isQueued
                ? "It's in \(plan.base)'s merge queue, which merges it once the queue's checks pass."
                : "GitHub merges it into \(plan.base) once required checks and reviews pass."
        ) {
            if plan.canDequeue {
                Button(model.busy.contains("merge") ? "Removing…" : "Remove from Queue") {
                    Task { _ = await model.dequeue() }
                }
                .buttonStyle(.ds(.secondary))
            } else if plan.canCancelAutoMerge {
                Button(model.busy.contains("merge") ? "Cancelling…" : "Cancel Auto-Merge") {
                    Task { _ = await model.disableAutoMerge() }
                }
                .buttonStyle(.ds(.secondary))
            }
        }
        .disabled(model.busy.contains("merge"))
    }

    @ViewBuilder private func options(_ page: PullRequestPage, plan: PullRequestMergePlan) -> some View {
        if plan.methods.count > 1, plan.action != .enqueue {
            Picker("Merge method", selection: Binding(get: { method ?? defaultMethod(page) }, set: { method = $0 })) {
                ForEach(plan.methods, id: \.self) { method in
                    Text(title(method)).tag(method)
                }
            }
            .pickerStyle(.segmented)
        }
        if case .merge = plan.action {
            GitHubCheckbox(title: "Delete \(page.headRefName) on GitHub after merging", isOn: $deletesBranch)
        }
        if let explanation = plan.explanation {
            // Names the commit too: a push since it was checked fails instead of merging unseen.
            Text(verbatim: "\(explanation) At \(page.headRefOid.prefix(7)), the latest commit when this was checked.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footer(_ plan: PullRequestMergePlan) -> some View {
        HStack(spacing: DS.Space.md) {
            if plan.adminMerge != nil, plan.state == nil {
                Button("Merge Now as Admin…") { isConfirmingAdminMerge = true }
                    .buttonStyle(.ds(.ghost, size: .medium))
                    .disabled(model.busy.contains("merge") || model.isLoading)
                    .confirmationDialog(
                        "Merge now, skipping \(plan.route == .queue ? "the merge queue" : "unmet requirements")?",
                        isPresented: $isConfirmingAdminMerge, titleVisibility: .visible
                    ) {
                        Button("Merge Now", role: .destructive) {
                            Task { await perform(.merge(plan.adminMerge ?? .merge), admin: true) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Your admin rights let this merge into \(plan.base) right away, without waiting for \(plan.route == .queue ? "the queue's checks" : "approvals or required checks")."
                        )
                    }
            }
            Spacer()
            Button(plan.state == nil ? "Cancel" : "Done") { dismiss() }
                .buttonStyle(.ds(.ghost, size: .medium))
            if let action = plan.action {
                Button(model.busy.contains("merge") ? busyTitle(action) : model.isLoading ? "Checking…" : plan.title) {
                    Task { await perform(action) }
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .disabled(model.busy.contains("merge") || model.isLoading)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
    }

    private func perform(_ action: PullRequestMergePlan.Action, admin: Bool = false) async {
        let done =
            switch action {
            case .enqueue: await model.enqueue()
            case .enableAutoMerge(let method): await model.enableAutoMerge(method)
            case .merge(let method): await model.merge(method, deleteBranch: deletesBranch, admin: admin)
            }
        if done { dismiss() }
    }

    private func busyTitle(_ action: PullRequestMergePlan.Action) -> String {
        switch action {
        case .enqueue: "Adding to Queue…"
        case .enableAutoMerge: "Turning On Auto-Merge…"
        case .merge: "Merging…"
        }
    }

    private func defaultMethod(_ page: PullRequestPage) -> MergeMethod {
        page.defaultMergeMethod.flatMap { page.mergeMethods.contains($0) ? $0 : nil } ?? page.mergeMethods.first
            ?? .merge
    }

    private func title(_ method: MergeMethod) -> String {
        switch method {
        case .merge: "Merge Commit"
        case .squash: "Squash"
        case .rebase: "Rebase"
        }
    }
}
