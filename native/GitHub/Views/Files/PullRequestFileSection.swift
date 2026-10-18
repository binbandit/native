import GitHub
import SwiftUI

/// One file on Files Changed: a header to fold it, mark it viewed or open it on GitHub, then its
/// diff with conversations on their lines. A file without a diff says why.
struct PullRequestFileSection: View {
    let model: PullRequestPageModel
    let file: ChangedFile

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        let collapsed = model.isCollapsed(file)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header(collapsed: collapsed)
            if !collapsed {
                SeparatorLine()
                content
            }
        }
        .background(.dsDiffBackground, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .task(id: collapsed) {
            if !collapsed { await model.loadPatch(for: file.path) }
        }
    }

    private func header(collapsed: Bool) -> some View {
        let folder = (file.path as NSString).deletingLastPathComponent
        let name = (file.path as NSString).lastPathComponent
        return HStack(spacing: DS.Space.sm) {
            Button {
                withAnimation(.dsDisclosure) { model.setCollapsed(!collapsed, file) }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: DS.Size.navIcon - DS.Space.xs, weight: .semibold))
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Size.navIcon)
                    Text(
                        "\(Text(folder.isEmpty ? "" : folder + "/").foregroundStyle(.dsTextTertiary))\(Text(name).foregroundStyle(.dsTextPrimary))"
                    )
                    .font(.dsMonoCaption)
                    .lineLimit(1)
                    .truncationMode(.head)
                    if file.isGenerated {
                        Badge("Generated", style: .outline)
                    }
                    Spacer(minLength: DS.Space.md)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(file.path), \(collapsed ? "folded" : "unfolded")")
            DiffStatLabel(added: file.additions, removed: file.deletions)
            GitHubCheckbox(
                title: "Viewed",
                isOn: Binding(get: { file.isViewed }, set: { viewed in Task { await model.setViewed(viewed, file) } })
            )
            .help("Mark this file viewed on GitHub. It folds, and unfolds again if the file changes.")
            Menu {
                Button("Copy Path", systemImage: "doc.on.doc") { gitHub.copy(file.path) }
                Button("Open on GitHub", systemImage: "arrow.up.right") {
                    gitHub.openExternally(model.reference.url.appending(path: "files"))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.dsTextSecondary)
            .accessibilityLabel("File Options")
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.xs)
        .frame(minHeight: DS.Size.controlMD)
    }

    @ViewBuilder private var content: some View {
        if let patch = model.patches[file.path] {
            if let reason = patch.missingPatchReason {
                missing(reason)
            } else if model.isLarge(file.path), !model.loadedLargeDiffs.contains(file.path) {
                largeDiff
            } else {
                PullRequestPatchView(model: model, path: file.path, hunks: model.hunks[file.path] ?? [])
            }
            outdatedThreads
        } else if model.patchesComplete {
            missing(.tooLarge)
        } else {
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                Text("Loading diff…")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(DS.Space.lg)
        }
    }

    private func missing(_ reason: FilePatch.MissingPatchReason) -> some View {
        let text =
            switch reason {
            case .binary: "Binary file. There's no text diff to show."
            case .tooLarge: "This diff is too large for GitHub to send. Open it on GitHub to see it."
            case .renamedOnly: "Renamed without changes."
            }
        return HStack(spacing: DS.Space.md) {
            Text(text)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
            Spacer(minLength: DS.Space.md)
            if reason == .tooLarge {
                Button("Open on GitHub") { gitHub.openExternally(model.reference.url.appending(path: "files")) }
                    .buttonStyle(.ds(.secondary))
            }
        }
        .padding(DS.Space.lg)
    }

    /// Big and minified diffs wait for a click, as on GitHub, so they don't slow the list.
    private var largeDiff: some View {
        HStack(spacing: DS.Space.md) {
            Text("Large diff: \(model.lineCount(file.path)) lines. It isn't shown until you load it.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
            Spacer(minLength: DS.Space.md)
            Button("Load Diff") { model.loadedLargeDiffs.insert(file.path) }
                .buttonStyle(.ds(.secondary))
        }
        .padding(DS.Space.lg)
    }

    /// Conversations whose lines are no longer in the diff, kept so nothing said goes missing.
    @ViewBuilder private var outdatedThreads: some View {
        let hunks = model.hunks[file.path] ?? []
        let orphans = model.threads(in: file.path).filter { thread in
            guard let anchor = thread.anchor else { return true }
            return !hunks.contains { $0.index(side: anchor.side, line: anchor.line) != nil }
        }
        if !orphans.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(orphans) { thread in
                    PullRequestReviewThreadView(model: model, thread: thread, showsAnchor: true)
                }
            }
            .padding(DS.Space.md)
        }
    }
}
