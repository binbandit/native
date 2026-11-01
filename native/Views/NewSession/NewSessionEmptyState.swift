import Git
import GitHub
import SwiftUI

/// What an empty transcript shows. A session's own transcript is a new session waiting for its
/// first message: `NewSessionView`, with the project's real ways to begin. Anywhere else (a
/// subagent, a workflow's run that hasn't started), that nothing's been said yet.
struct NewSessionEmptyState: View {
    let session: SessionModel

    @Environment(\.isPrimaryTranscript) private var isPrimary

    var body: some View {
        if isPrimary, session.isProjectless {
            NoProjectTaskIntro(session: session)
        } else if isPrimary {
            NewSessionScreen(session: session)
        } else {
            NewSessionNothingYet()
        }
    }
}

/// An empty conversation that isn't a new session of the user's.
private struct NewSessionNothingYet: View {
    var body: some View {
        EmptyStateView(
            "No messages yet", systemImage: "text.bubble", message: "The conversation shows here once it starts.")
    }
}

/// A new session's starting points in the transcript's column, resting on the composer. It
/// scrolls when the window is too short for it, showing the end nearest the composer first.
private struct NewSessionScreen: View {
    let session: SessionModel

    @Environment(AppModel.self) private var model
    @Environment(GitStore.self) private var git
    @Environment(GitHubModel.self) private var gitHub
    @Environment(ProjectActionRunner.self) private var runner
    @Environment(TaskScriptCenter.self) private var scripts
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.transcriptColumnMaxWidth) private var columnWidth
    @Environment(\.dsDrawsToolbarBand) private var drawsToolbarBand
    /// The project's repositories on GitHub, read from its remotes once it's shown.
    @State private var repositories: [String] = []
    @State private var height: CGFloat = 0

    var body: some View {
        if let project {
            let context = NewSessionContextBuilder(
                session: session, project: project, model: model, git: git, gitHub: gitHub, runner: runner,
                scripts: scripts, settings: settings, repositories: repositories
            ).context()
            ScrollView {
                NewSessionView(context: context)
                    .frame(maxWidth: columnWidth, alignment: .leading)
                    .padding(.horizontal, DS.Space.xxl)
                    .padding(.top, DS.Space.xxl)
                    .padding(.bottom, DS.Space.xxxl)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: .bottom)
            }
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectHidden(drawsToolbarBand, for: .top)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                self.height = height
            }
            .task(id: project.url) {
                repositories = await Self.repositories(of: git.model(for: project.url))
            }
        } else {
            NewSessionNothingYet()
        }
    }

    private var project: Project? {
        model.catalog.lookup(session.key).flatMap { model.projects.project($0.project) }
    }

    /// The `owner/name` of each remote that's on a host, origin first, lowercased to match pull
    /// requests by. Reads the remotes once git has opened the repository.
    private static func repositories(of checkout: GitRepositoryModel) async -> [String] {
        if checkout.repository == nil { await checkout.refreshNow() }
        guard let remotes = try? await checkout.repository?.remoteURLs() else { return [] }
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        var names: [String] = []
        for remote in ordered {
            guard let name = RemoteRepository(remoteURL: remote.url)?.nameWithOwner.lowercased(),
                !names.contains(name)
            else { continue }
            names.append(name)
        }
        return names
    }
}

#if DEBUG
#Preview("New task - No conversation") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        if let session = SessionModel.preview(in: app) {
            NewSessionEmptyState(session: session)
                .environment(\.isPrimaryTranscript, false)
                .frame(width: DS.Size.popoverWidth)
        }
    }
}
#endif
