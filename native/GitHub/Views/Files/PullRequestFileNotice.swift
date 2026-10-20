import GitHub
import SwiftUI

/// What stands in for a file's diff when there isn't one to draw yet: loading, missing (binary,
/// too large for GitHub, renamed only), or large and waiting for "Load Diff".
struct PullRequestFileNotice: View {
    enum Kind {
        case loading
        case missing(FilePatch.MissingPatchReason)
        case large(lines: Int)
    }

    let model: PullRequestPageModel
    let path: String
    let kind: Kind

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        HStack(spacing: DS.Space.md) {
            switch kind {
            case .loading:
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                Text("Loading diff…")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            case .missing(let reason):
                Text(text(reason))
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.md)
                if reason == .tooLarge {
                    Button("Open on GitHub") { gitHub.openExternally(model.reference.url.appending(path: "files")) }
                        .buttonStyle(.ds(.secondary))
                }
            case .large(let lines):
                // Big and minified diffs without conversations wait for a click, as on GitHub.
                Text("Large diff: \(lines) lines. It isn't shown until you load it.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.md)
                Button("Load Diff") { model.loadedLargeDiffs.insert(path) }
                    .buttonStyle(.ds(.secondary))
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ reason: FilePatch.MissingPatchReason) -> String {
        switch reason {
        case .binary: "Binary file. There's no text diff to show."
        case .tooLarge: "This diff is too large for GitHub to send. Open it on GitHub to see it."
        case .renamedOnly: "Renamed without changes."
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("File notices") {
    DSPreviewPair {
        PullRequestPagePreview { model, _ in
            VStack(spacing: DS.Space.md) {
                PullRequestFileNotice(model: model, path: "native/Views/Composer/ComposerView.swift", kind: .loading)
                PullRequestFileNotice(model: model, path: "design/composer/queued.png", kind: .missing(.binary))
                PullRequestFileNotice(model: model, path: "Packages/ACP/schema.json", kind: .missing(.tooLarge))
                PullRequestFileNotice(model: model, path: "docs/old-notes.md", kind: .missing(.renamedOnly))
                PullRequestFileNotice(model: model, path: "native/Resources/Grammars.json", kind: .large(lines: 18_204))
            }
        }
        .frame(width: 760)
    }
}
#endif
