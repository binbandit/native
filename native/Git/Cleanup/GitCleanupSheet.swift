import Git
import SwiftUI

extension View {
    /// The Clean Up Merged sheet, over the window while a project's cleanup is open.
    func gitCleanupSheet(_ center: GitCleanupCenter) -> some View {
        sheet(isPresented: Binding(get: { center.presented != nil }, set: { if !$0 { center.close() } })) {
            if let model = center.presented {
                GitCleanupSheet(center: center, model: model)
            }
        }
    }
}

/// Clean Up Merged for a project: what's merged, grouped by what will happen to it, each item with
/// why it qualifies; then the work, item by item; failures stay in the sheet beside their items.
struct GitCleanupSheet: View {
    let center: GitCleanupCenter
    let model: GitCleanupModel

    @State private var showsKept = false

    var body: some View {
        VStack(spacing: 0) {
            header
            SeparatorLine()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SeparatorLine()
            footer
        }
        .frame(width: GitCleanupMetrics.sheetWidth, height: GitCleanupMetrics.sheetHeight)
        .background(.dsBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Clean Up Merged")
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text(subtitle)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.lg)
            IconButton("Close", systemImage: "xmark") { center.close() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.leading, DS.Space.xl)
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .frame(minHeight: DS.Window.headerHeight + DS.Space.md)
    }

    private var subtitle: String {
        guard let plan = model.plan else { return model.project.name }
        return "\(model.project.name) · branches, worktrees and folders whose work is in \(plan.base)"
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .scanning(let step):
            VStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: GitMetrics.loaderLarge, height: GitMetrics.loaderLarge)
                Text(step)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
        case .unavailable(let reason):
            EmptyStateView("Nothing to Clean Up", systemImage: "arrow.triangle.branch", message: reason)
        case .failed(let details):
            ErrorState(
                "Couldn't look for merged work in “\(model.project.name)”",
                recovery: "Nothing was changed.",
                details: details,
                primary: .init("Try Again") { rescan() },
                layout: .pane)
        case .review, .running, .finished:
            if model.items.isEmpty {
                EmptyStateView(
                    "Nothing to Clean Up", systemImage: "checkmark.circle",
                    message: emptyMessage, actionTitle: "Check Again"
                ) { rescan() }
                .overlay(alignment: .bottom) { kept.padding(DS.Space.lg) }
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if case .unavailable(let reason)? = model.plan?.pullRequestCheck, let plan = model.plan {
                    NoticeBanner(
                        tone: .info, systemImage: "info.circle",
                        title: "Squash and rebase merges were found by comparing content",
                        detail: "GitHub couldn't be asked (\(reason)), so a pushed branch counts as merged when "
                            + "merging it into \(plan.base) would change nothing.")
                }
                ForEach(GitCleanupItem.Group.allCases) { group in
                    if !model.shownItems(in: group).isEmpty {
                        GitCleanupGroupSection(model: model, group: group)
                    }
                }
                kept
            }
            .padding(DS.Space.lg)
        }
    }

    private var emptyMessage: String {
        let base = model.plan?.base ?? "the main branch"
        return "No task worktree or branch in “\(model.project.name)” is merged into \(base), and git's worktree "
            + "records are tidy. Native looks again each time you open this."
    }

    /// Native's branches and worktrees that stay, and why, so nothing the user expected goes
    /// unexplained.
    @ViewBuilder private var kept: some View {
        if let plan = model.plan, !plan.kept.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Button {
                    withAnimation(.dsPanel) { showsKept.toggle() }
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "chevron.right")
                            .font(.dsCaption)
                            .rotationEffect(.degrees(showsKept ? 90 : 0))
                        Text(
                            plan.kept.count == 1
                                ? "Kept 1 of Native's branches" : "Kept \(plan.kept.count) of Native's branches"
                        )
                        .font(.dsBody)
                    }
                    .foregroundStyle(.dsTextTertiary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .dsHitTarget(DS.Size.controlXS)
                .accessibilityValue(showsKept ? "Expanded" : "Collapsed")
                if showsKept {
                    ForEach(plan.kept) { kept in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                            Text(kept.branch ?? kept.worktree?.lastPathComponent ?? "")
                                .font(.dsMonoCaption)
                                .foregroundStyle(.dsTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: DS.Space.md)
                            Text(GitCleanupItem.describe(kept.why, base: plan.base))
                                .font(.dsCaption)
                                .foregroundStyle(.dsTextTertiary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.leading, DS.Space.lg)
                    }
                }
            }
            .padding(.horizontal, DS.Space.md)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            status
            Spacer(minLength: DS.Space.md)
            switch model.phase {
            case .review where !model.items.isEmpty:
                Button("Cancel", role: .cancel) { center.close() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                Button(cleanUpTitle) { center.cleanUp(model) }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.included.isEmpty)
            case .running:
                Button("Close") { center.close() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .help("Cleaning up carries on in the background.")
            case .finished:
                if model.undoRecord?.isEmpty == false {
                    Button("Undo") {
                        Task { await model.undo() }
                        center.close()
                    }
                    .buttonStyle(.ds(.secondary, size: .medium))
                }
                Button("Done") { center.close() }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Done") { center.close() }
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
        .padding(DS.Space.lg)
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .review where !model.items.isEmpty:
            Text(totals)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        case .running:
            let total = model.included.count
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
                Text("Cleaning up \(min(model.doneCount + model.failureCount + 1, total)) of \(total)…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
        case .finished:
            let failed = model.failureCount
            Text(
                failed == 0
                    ? "Cleaned up \(model.doneCount == 1 ? "1 item" : "\(model.doneCount) items")."
                    : "Cleaned up \(model.doneCount) of \(model.states.count). "
                        + "\(failed == 1 ? "1 item was" : "\(failed) items were") left as they were."
            )
            .font(.dsBody)
            .foregroundStyle(failed == 0 ? .dsTextSecondary : .dsDanger)
        default:
            EmptyView()
        }
    }

    private var totals: String {
        let count = model.included.count
        guard count > 0 else { return "Nothing included" }
        let items = count == 1 ? "1 item" : "\(count) items"
        let bytes = model.reclaimedBytes
        return bytes > 0 ? "\(items) · \(DSFormat.fileSize(bytes)) reclaimed" : items
    }

    private var cleanUpTitle: String {
        switch model.included.count {
        case 0: "Clean Up"
        case 1: "Clean Up 1 Item"
        case let count: "Clean Up \(count) Items"
        }
    }

    private func rescan() {
        model.work = Task { await model.scan() }
    }
}
