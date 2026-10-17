import Git
import SwiftUI

/// The commit form (after the reference app's commit box): a message, which files go in, and Commit, Commit &
/// Push, or Commit & Create PR when the GitHub feature provides one. The on-device model can draft
/// the message from the selected files' diff.
struct GitCommitPopover: View {
    @Bindable var model: GitRepositoryModel
    @Binding var isPresented: Bool
    let onCreatePullRequest: (() -> Void)?

    @State private var selected: Set<String> = []
    @State private var isDrafting = false
    @State private var isCommitting = false
    @State private var notice: GitNotice?
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        let files = GitCommitFile.files(from: model.changes)
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header
            messageEditor
            fileList(files)
            if let notice {
                GitNoticeBanner(
                    notice: notice,
                    onAction: { action in
                        isPresented = false
                        Task { await model.run(action) }
                    }, onDismiss: { self.notice = nil }
                )
                .clipShape(.rect(cornerRadius: DS.Radius.control, style: .continuous))
            }
            SeparatorLine()
            footer(files)
        }
        .padding(DS.Space.lg)
        .frame(width: GitMetrics.commitWidth)
        .background(.dsOverlay)
        .disabled(isCommitting)
        .onAppear {
            selected = GitCommitFile.defaultSelection(from: model.changes)
            isMessageFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Text("Commit to \(model.branch?.displayName ?? "HEAD")")
                .font(.dsHeadline)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.md)
            if isDrafting {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsAccentText)
                    .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
                    .help("Drafting a message…")
            } else if CommitMessageDrafter.isAvailable {
                IconButton("Draft Message with Apple Intelligence", systemImage: "sparkles") {
                    Task { await draft() }
                }
                .dsHitTarget(DS.Size.controlXS)
                .disabled(selected.isEmpty)
            }
        }
    }

    private var messageEditor: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        return TextEditor(text: $model.commitMessage)
            .font(.dsCallout)
            .scrollContentBackground(.hidden)
            .focused($isMessageFocused)
            .accessibilityLabel("Commit message")
            .padding(DS.Space.sm)
            .frame(height: GitMetrics.commitMessageHeight)
            .background(.dsSurface, in: shape)
            .overlay(alignment: .topLeading) {
                if model.commitMessage.isEmpty {
                    Text("Commit message")
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.horizontal, DS.Space.sm + GitMetrics.textEditorInset)
                        .padding(.vertical, DS.Space.sm)
                        .allowsHitTesting(false)
                }
            }
            .overlay { shape.strokeBorder(isMessageFocused ? Color.dsBorderHover : .dsBorder, lineWidth: 1) }
    }

    private func fileList(_ files: [GitCommitFile]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                GitCheckbox(value: selectAllValue(files), label: "Select All Files") {
                    selected = selected.count == files.count ? [] : Set(files.map(\.path))
                }
                Text("\(selected.count) of \(files.count) files")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.md)
                let totals = files.filter { selected.contains($0.path) }.reduce(LineStats.zero) { $0 + $1.stats }
                DiffStatLabel(added: totals.additions, removed: totals.deletions)
            }
            .padding(.horizontal, DS.Space.sm)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        row(file)
                    }
                }
            }
            .frame(maxHeight: GitMetrics.commitFileListMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ file: GitCommitFile) -> some View {
        let isOn = selected.contains(file.path)
        return HStack(spacing: DS.Space.sm) {
            GitCheckbox(value: isOn ? .on : .off, label: file.path) { toggle(file.path) }
            GitPathLabel(path: file.path, font: .dsBody)
                .frame(maxWidth: .infinity, alignment: .leading)
            DiffStatLabel(added: file.stats.additions, removed: file.stats.deletions)
            GitStatusGlyph(kind: file.kind)
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(height: DS.Size.controlXS)
        .contentShape(.rect)
        .onTapGesture { toggle(file.path) }
    }

    private func footer(_ files: [GitCommitFile]) -> some View {
        let canCommit =
            !selected.isEmpty && !model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: DS.Space.sm) {
            if let onCreatePullRequest, model.branch?.isDetached == false {
                Button("Commit & Create PR") {
                    Task { await commit(files, push: true, then: onCreatePullRequest) }
                }
                .buttonStyle(.ds(.ghost))
                .disabled(!canCommit)
            }
            Spacer(minLength: DS.Space.md)
            if isCommitting {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
            }
            Button("Commit & Push") {
                Task { await commit(files, push: true) }
            }
            .buttonStyle(.ds(.secondary))
            .disabled(!canCommit || model.branch?.isDetached != false)
            Button("Commit") {
                Task { await commit(files, push: false) }
            }
            .buttonStyle(.ds(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canCommit)
        }
    }

    // MARK: - Actions

    private func selectAllValue(_ files: [GitCommitFile]) -> GitCheckbox.Value {
        selected.isEmpty ? .off : selected.count == files.count ? .on : .mixed
    }

    private func toggle(_ path: String) {
        if selected.remove(path) == nil { selected.insert(path) }
    }

    private func draft() async {
        isDrafting = true
        defer { isDrafting = false }
        let changes = model.changes.filter { selected.contains($0.path) }
        do {
            model.commitMessage = try await model.draftCommitMessage(for: changes)
            notice = nil
        } catch {
            notice = GitNotice(tone: .failure, title: "Couldn't draft a message", message: error.localizedDescription)
        }
    }

    private func commit(_ files: [GitCommitFile], push: Bool, then next: (() -> Void)? = nil) async {
        isCommitting = true
        defer { isCommitting = false }
        let changes = files.filter { selected.contains($0.path) }.flatMap(\.changes)
        do {
            try await model.commit(message: model.commitMessage, files: changes, push: push)
            isPresented = false
            next?()
        } catch {
            notice = GitNotice(failure: error, during: .commit)
        }
    }
}
