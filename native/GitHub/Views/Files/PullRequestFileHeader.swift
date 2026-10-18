import GitHub
import SwiftUI

/// A file's header on Files Changed: fold it, see its size, wrap its long lines, mark it viewed,
/// copy its path or open it on GitHub. Opening it loads its diff.
struct PullRequestFileHeader: View {
    let model: PullRequestPageModel
    let file: ChangedFile

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        if UserDefaults.standard.bool(forKey: "gitHubExperimentSimpleHeader") {
            Text(file.path).frame(maxWidth: .infinity, minHeight: DS.Size.controlMD, alignment: .leading)
                .task(id: model.isCollapsed(file)) { await model.loadPatch(for: file.path) }
        } else {
            full
        }
    }

    @ViewBuilder private var full: some View {
        let collapsed = model.isCollapsed(file)
        let folder = (file.path as NSString).deletingLastPathComponent
        let name = (file.path as NSString).lastPathComponent
        HStack(spacing: DS.Space.sm) {
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
            if !collapsed {
                IconButton(
                    model.wraps(file.path) ? "Don't Wrap Lines" : "Wrap Lines", systemImage: "arrow.turn.down.left",
                    isActive: model.wraps(file.path)
                ) {
                    model.toggleWrapping(file.path)
                }
                .help("Wrap long lines in this file, or cut them off at the edge with … to open one at a time")
            }
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
        .overlay(alignment: .bottom) {
            if !collapsed { SeparatorLine() }
        }
        .task(id: collapsed) {
            if !collapsed { await model.loadPatch(for: file.path) }
        }
    }
}
