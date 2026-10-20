import Git
import GitHub
import SwiftUI

/// What an empty transcript shows. For a new session's own transcript, the design under review
/// (`NewSessionDesign`); everywhere else, and for users until one is picked, the centered prompt.
struct NewSessionEmptyState: View {
    let session: SessionModel

    @Environment(\.isPrimaryTranscript) private var isPrimary

    var body: some View {
        if isPrimary, NewSessionDesign.current != .today {
            NewSessionDesignedState(session: session, design: NewSessionDesign.current)
        } else {
            NewSessionTodayState(session: session)
        }
    }
}

/// Today's empty state: a prompt over the task's folder.
private struct NewSessionTodayState: View {
    let session: SessionModel

    var body: some View {
        ContentUnavailableView(
            "What should we work on?", systemImage: "sparkles", description: Text(session.cwd.abbreviatedPath))
    }
}

/// A design under review, laid out in the transcript's column: the workbench from the top, the
/// others resting on the composer. It scrolls when the window is too short for it, showing the
/// end nearest the composer first.
private struct NewSessionDesignedState: View {
    let session: SessionModel
    let design: NewSessionDesign

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
            let anchor: Alignment = design == .workbench ? .top : .bottom
            ScrollView {
                content(context)
                    .frame(maxWidth: columnWidth, alignment: .leading)
                    .padding(.horizontal, DS.Space.xxl)
                    .padding(.top, DS.Space.xxl)
                    .padding(.bottom, NewSessionMetrics.composerGap)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: anchor)
            }
            .defaultScrollAnchor(design == .workbench ? .top : .bottom)
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
            NewSessionTodayState(session: session)
        }
    }

    @ViewBuilder private func content(_ context: NewSessionContext) -> some View {
        switch design {
        case .today: EmptyView()
        case .focus: NewSessionFocusView(context: context)
        case .workbench: NewSessionWorkbenchView(context: context)
        case .startingPoints: NewSessionStartingPointsView(context: context)
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
