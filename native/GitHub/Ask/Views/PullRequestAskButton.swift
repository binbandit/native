import GitHub
import SwiftUI

/// "Ask" in a pull request page's header: shows or hides the private question panel, and reads as
/// pressed while it's open. Nothing when the feature isn't connected (previews, tests).
struct PullRequestAskButton: View {
    let reference: PullRequestReference

    @Environment(PullRequestAskCenter.self) private var center: PullRequestAskCenter?

    var body: some View {
        if let center, center.isConnected {
            let isOpen = center.isPanelOpen(for: reference)
            Button {
                withAnimation(.dsStandard) { center.togglePanel(for: reference) }
            } label: {
                Label("Ask", systemImage: "questionmark.bubble")
            }
            .buttonStyle(.ds(isOpen ? .primary : .secondary))
            .help(
                isOpen
                    ? "Hide your private questions about this pull request"
                    : "Ask an agent about this pull request. Only you see the answers; nothing is posted."
            )
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            .keyboardShortcut("a", modifiers: [.command, .option])
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask button") {
    let app = AppModel.preview()
    let gitHub = GitHubModel.preview()
    let closed = PullRequestAskPreviewFixtures.center()
    closed.connect(app: app, gitHub: gitHub)
    let open = PullRequestAskPreviewFixtures.center()
    open.connect(app: app, gitHub: gitHub)
    open.togglePanel(for: PullRequestPreviewRunner.reference)
    return DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            PullRequestAskButton(reference: PullRequestPreviewRunner.reference)
                .environment(closed)
            PullRequestAskButton(reference: PullRequestPreviewRunner.reference)
                .environment(open)
        }
    }
    .environment(app)
    .environment(gitHub)
}
#endif
