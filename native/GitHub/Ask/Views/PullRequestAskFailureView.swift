import ACP
import GitHub
import SwiftUI

/// Why the last question didn't go out, above the composer that still holds it: what happened,
/// what Native did, and the one action that gets the question answered.
struct PullRequestAskFailureView: View {
    let conversation: PullRequestAskConversation
    let failure: PullRequestAskFailure

    var body: some View {
        switch failure {
        case .noAgent:
            ErrorState(
                "No agent to ask",
                recovery: "Questions go to your default agent, and none is installed yet.",
                suggestion: "Add one, then ask again. Your question is kept.",
                primary: .init("Add Agent…") { conversation.addAgent() },
                secondary: .init("Try Again") { retry() })
        case .agentUnavailable(let agent, let name, let guidance):
            ErrorState(
                "\(name) isn't running",
                recovery: "Your question is kept.",
                suggestion: guidance ?? "Start it again, then Native asks your question.",
                primary: .init("Restart \(name)") { Task { await conversation.restartAgent(agent) } })
        case .signInRequired(let agent, let name):
            NoticeBanner(
                tone: .warning, systemImage: "person.badge.key", title: "Sign in to \(name) to ask",
                detail: "Your question is kept, and goes out once you're signed in."
            ) {
                signInButtons(agent: agent, name: name)
            }
        case .gitHub(let error):
            ErrorState(
                "The pull request didn't load",
                recovery: "Questions need its diff and comments, which gh couldn't read. Your question is kept.",
                suggestion: error.recoverySuggestion,
                details: error.stderr,
                primary: .init("Try Again") { retry() })
        case .workspace(let message):
            ErrorState(
                "Native couldn't save the pull request for \(conversation.agentName)",
                recovery: "Your question is kept.",
                suggestion: "Check that your disk has space, then try again.",
                details: message,
                primary: .init("Try Again") { retry() })
        case .startFailed(let name, let message):
            ErrorState(
                "\(name) couldn't start a conversation",
                recovery: "Your question is kept.",
                suggestion: "Try again in a moment.",
                details: message,
                primary: .init("Try Again") { retry() })
        case .reopenFailed(let name, let message):
            ErrorState(
                "Your earlier conversation didn't reopen",
                recovery: "\(name) couldn't load it. It's still in \(name)'s history, and in Search.",
                suggestion: "Start a new conversation here, or try again.",
                details: message,
                primary: .init("New Conversation") { conversation.startOver() },
                secondary: .init("Try Again") { retry() })
        }
    }

    @ViewBuilder private func signInButtons(agent: AgentDefinition.ID, name: String) -> some View {
        let methods = conversation.signInMethods(for: agent)
        if methods.count > 1 {
            Menu("Sign In") {
                ForEach(methods, id: \.id) { method in
                    Button(method.name) { Task { await conversation.signIn(to: agent, with: method) } }
                }
            }
            .buttonStyle(.ds(.primary))
            .fixedSize()
        } else if let method = methods.first {
            Button("Sign In") { Task { await conversation.signIn(to: agent, with: method) } }
                .buttonStyle(.ds(.primary))
        }
        Button("Try Again") { retry() }
            .buttonStyle(.ds(.ghost))
    }

    private func retry() {
        Task { await conversation.retry() }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask failures") {
    let center = PullRequestAskPreviewFixtures.center()
    let conversation = center.conversation(for: PullRequestPreviewRunner.reference)
    let claude = AgentDefinition.ID(rawValue: "claude-code")
    let failures: [PullRequestAskFailure] = [
        .noAgent,
        .agentUnavailable(agent: claude, name: "Claude Code", guidance: nil),
        .signInRequired(agent: claude, name: "Claude Code"),
        .gitHub(.offline("error connecting to api.github.com")),
        .workspace("Native couldn't make a folder for the conversation: the disk is full."),
        .startFailed(name: "Claude Code", message: "The agent exited before it answered (code 1)."),
        .reopenFailed(name: "Codex", message: "Task not found"),
    ]
    return DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(failures.indices, id: \.self) { index in
                PullRequestAskFailureView(conversation: conversation, failure: failures[index])
            }
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
    .environment(center)
}
#endif
