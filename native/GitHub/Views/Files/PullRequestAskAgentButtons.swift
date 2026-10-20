import GitHub
import SwiftUI

/// "Ask an Agent in a New Task" and "Send to Current Task", for menus on lines and threads. The
/// agent gets the lines as diff and any review comments on them.
struct PullRequestAskAgentButtons: View {
    let model: PullRequestPageModel
    let anchor: ReviewAnchor
    let thread: ReviewThread?
    var request: String?

    var body: some View {
        Button(thread == nil ? "Ask an Agent in a New Task" : "Ask an Agent to Address This", systemImage: "sparkles") {
            Task { await model.askAgent(about: anchor, thread: thread, request: request, destination: .newTask) }
        }
        .help("Starts a task in a checkout of this branch with these lines and comments")
        if model.canSendToCurrentTask {
            Button("Send to Current Task", systemImage: "arrow.turn.down.right") {
                Task {
                    await model.askAgent(about: anchor, thread: thread, request: request, destination: .currentTask)
                }
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask an agent") {
    DSPreviewPair {
        PullRequestPagePreview { model, page in
            HStack(spacing: DS.Space.lg) {
                Menu("Lines") {
                    PullRequestAskAgentButtons(
                        model: model,
                        anchor: ReviewAnchor(
                            path: "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift", side: .right, line: 18,
                            startLine: 16),
                        thread: nil)
                }
                Menu("A conversation") {
                    if let thread = page.threads.first, let anchor = thread.anchor {
                        PullRequestAskAgentButtons(model: model, anchor: anchor, thread: thread)
                    }
                }
            }
            .fixedSize()
        }
    }
}
#endif
