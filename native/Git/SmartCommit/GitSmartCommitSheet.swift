import Git
import SwiftUI

/// Smart Commit: the working changes split into logical commits, each with a drafted message, to
/// review and edit before anything is committed. The commits are made in order after a checkpoint,
/// and the inspector then offers to undo them all.
struct GitSmartCommitSheet: View {
    @State private var plan: GitSmartCommitModel
    @Environment(\.dismiss) private var dismiss

    init(repository: GitRepositoryModel) {
        _plan = State(initialValue: GitSmartCommitModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SeparatorLine()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    if let note = plan.note {
                        Text(note)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    ForEach(Array(plan.groups.enumerated()), id: \.element.id) { index, group in
                        GitCommitGroupCard(model: plan, group: group, number: index + 1)
                    }
                    excluded
                }
                .padding(DS.Space.lg)
            }
            .overlay {
                if plan.phase == .drafting {
                    VStack(spacing: DS.Space.md) {
                        DotGridLoader(pattern: .typing)
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: GitMetrics.loaderLarge, height: GitMetrics.loaderLarge)
                        Text("Grouping \(plan.files.count) files into commits…")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.dsBackground)
                }
            }
            if let failure = plan.failure {
                GitNoticeBanner(notice: failure, onAction: { action in Task { await plan.repository.run(action) } })
            }
            SeparatorLine()
            footer
        }
        .frame(width: GitMetrics.smartCommitWidth, height: GitMetrics.smartCommitHeight)
        .background(.dsBackground)
        .task { await plan.draft() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Smart Commit")
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text(summary)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
            Spacer(minLength: DS.Space.md)
            IconButton("Group Again", systemImage: "sparkles") {
                Task { await plan.draft() }
            }
            .dsHitTarget(DS.Size.controlXS)
            .disabled(plan.phase != .ready)
        }
        .padding(DS.Space.lg)
    }

    @ViewBuilder private var excluded: some View {
        let files = plan.excluded
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Left uncommitted \(files.count)")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                ForEach(files) { file in
                    HStack(spacing: DS.Space.sm) {
                        GitCheckbox(value: .off, label: "Include \(file.path)") {
                            plan.move(file.path, to: plan.groups.last?.id)
                        }
                        GitPathLabel(path: file.path, font: .dsBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        DiffStatLabel(added: file.stats.additions, removed: file.stats.deletions)
                        GitStatusGlyph(kind: file.kind)
                        GitMoveFileMenu(model: plan, path: file.path, current: nil)
                    }
                    .frame(minHeight: DS.Size.controlXS)
                }
            }
            .padding(.horizontal, DS.Space.md)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            Spacer()
            if plan.phase == .committing {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
            }
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.ds(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(plan.groups.count == 1 ? "Make 1 Commit" : "Make \(plan.groups.count) Commits") {
                Task {
                    if await plan.commit() { dismiss() }
                }
            }
            .buttonStyle(.ds(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!plan.canCommit)
        }
        .padding(DS.Space.lg)
    }

    private var summary: String {
        guard plan.phase != .drafting else { return "Reading the changes." }
        let commits = plan.groups.count == 1 ? "1 commit" : "\(plan.groups.count) commits"
        let files = plan.files.count == 1 ? "1 file" : "\(plan.files.count) files"
        return "\(commits) from \(files). Nothing is committed until you confirm, and you can undo it after."
    }
}
