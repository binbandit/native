import SwiftUI

/// After creating: the new pull request's link and what to do with it.
struct CreatedPullRequestView: View {
    let url: URL
    let onCopy: () -> Void
    let onDone: () -> Void

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: DS.Size.composerPill - DS.Space.xs, weight: .light))
                .foregroundStyle(.dsSuccess)
            VStack(spacing: DS.Space.xs) {
                Text("Pull Request \(number) Created")
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                Text(url.absoluteString)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: DS.Space.md) {
                Button("Copy URL", systemImage: "link", action: onCopy)
                    .buttonStyle(.ds(.secondary, size: .medium))
                Button("Open on GitHub", systemImage: "arrow.up.right") { gitHub.openExternally(url) }
                    .buttonStyle(.ds(.secondary, size: .medium))
                Button("Done", action: onDone)
                    .buttonStyle(.ds(.primary, size: .medium))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxl)
    }

    private var number: String {
        Int(url.lastPathComponent).map { "#\($0)" } ?? ""
    }
}
