import ACP
import Foundation
import Git
import GitHub

/// Opening a pull request as a task, end to end: finding the project that's a checkout of its
/// repository, checking its head out in a new worktree the way `gh pr checkout` does (forks
/// included), and starting a task there that's briefed on the pull request. Opening it again finds
/// that task instead of making a second checkout, and can bring it up to date.
@MainActor
struct PullRequestTaskCheckout {
    let app: AppModel
    let git: GitStore
    let gitHub: GitHubModel

    /// The note kept with a task's branch (`branch.<name>.nativePullRequest`): the pull request's
    /// link, which finds the task again and gives its sidebar row the pull request's badge.
    static let linkNote = "nativePullRequest"

    /// What opening a pull request will do.
    enum Resolution {
        case existing(ExistingTask)
        case checkout(ProjectCheckout)
        case noProject(NoProject)
    }

    /// A task already working on the pull request.
    struct ExistingTask {
        let key: SessionKey
        let title: String
        let folder: URL
        let project: Project
        let details: PullRequestDetails
        let headState: PullRequestTaskMatch.HeadState
        let isArchived: Bool
    }

    /// A project to check the pull request out in.
    struct ProjectCheckout {
        let project: Project
        let details: PullRequestDetails
        let plan: PullRequestCheckoutPlan
        /// A worktree made for it before, whose task never started (the agent failed, say): used
        /// again rather than made twice.
        let reusableFolder: URL?
    }

    /// No project is a checkout of the pull request's repository.
    struct NoProject {
        let details: PullRequestDetails
        let repository: RemoteRepository
    }

    enum Step: Equatable {
        case lookingUp
        case cloning(String)
        case fetching
        case creatingWorktree
        case startingAgent(String)
        case updating

        var label: String {
            switch self {
            case .lookingUp: "Looking for the pull request's project…"
            case .cloning(let repository): "Cloning \(repository)…"
            case .fetching: "Fetching the pull request…"
            case .creatingWorktree: "Creating its worktree…"
            case .startingAgent(let agent): "Starting \(agent)…"
            case .updating: "Fetching the pull request's new commits…"
            }
        }
    }

    // MARK: - Resolving

    /// Looks the pull request up on GitHub and works out where it goes: the task already working
    /// on it, a project to check it out in, or nowhere yet. Changes nothing.
    func resolve(_ reference: PullRequestReference, rereadEnvironment: Bool = false) async throws -> Resolution {
        let cli = await gitHub.cli(rereadEnvironment: rereadEnvironment)
        let details = try await cli.pullRequestDetails(reference)
        let base =
            details.baseRepository
            ?? RemoteRepository(host: reference.host, owner: reference.owner, name: reference.name)
        var candidates: [PullRequestProjectMatch.Candidate<Project.ID>] = []
        for project in app.projects.all where project.host == .local {
            guard let repository = try? await git.requireRepository(at: project.url),
                let remotes = try? await repository.remoteURLs()
            else { continue }
            candidates.append(.init(id: project.id, remotes: remotes.map { GitRemote(name: $0.name, url: $0.url) }))
        }
        guard let match = PullRequestProjectMatch.best(base: base, head: details.headRepository, among: candidates),
            let project = app.projects.project(match.id),
            let remotes = candidates.first(where: { $0.id == match.id })?.remotes
        else {
            return .noProject(NoProject(details: details, repository: base))
        }

        let repository = try await git.requireRepository(at: project.url)
        let linked = try await linkedWorktrees(of: repository, to: reference)
        let sessions = app.allSessions(in: project.id)
        if let task = existingTask(for: reference, among: sessions, linked: linked) {
            let folder = URL(filePath: task.info.cwd, directoryHint: .isDirectory)
            return .existing(
                ExistingTask(
                    key: task.id, title: app.title(for: task), folder: folder, project: project, details: details,
                    headState: await headState(of: details, in: folder), isArchived: app.isArchived(task.id)))
        }
        let plan = PullRequestCheckoutPlan(
            details, remotes: remotes, viewer: await viewer(cli),
            permission: await permission(for: details, on: base, cli: cli))
        // A worktree made for it that no task runs in, not even one waiting out its deletion.
        let reusable = linked.first { worktree in
            !sessions.contains { SessionFolder.isSame($0.info.cwd, worktree.path.folderPath) }
        }
        return .checkout(
            ProjectCheckout(project: project, details: details, plan: plan, reusableFolder: reusable?.path))
    }

    /// The project's worktrees whose branch notes link them to the pull request.
    private func linkedWorktrees(
        of repository: Repository, to reference: PullRequestReference
    ) async throws
        -> [Worktree]
    {
        let notes = try await repository.notes(Self.linkNote)
        let branches = Set(
            notes.compactMap { branch, link in
                let linked = URL(string: link).flatMap(PullRequestReference.init(url:))
                return linked?.isSamePullRequest(as: reference) == true ? branch : nil
            })
        guard !branches.isEmpty else { return [] }
        return try await repository.worktrees().filter { worktree in
            !worktree.isMain && !worktree.isPrunable && worktree.branch.map(branches.contains) == true
        }
    }

    /// The task, in the sidebar or archived, whose folder is one of those worktrees.
    private func existingTask(
        for reference: PullRequestReference, among sessions: [SessionSummary], linked: [Worktree]
    ) -> SessionSummary? {
        let live = sessions.filter { !app.pendingDeletionKeys.contains($0.id) }
        // By position: session keys are main-actor types the package's matching can't hold.
        let candidates = live.enumerated().map { index, summary in
            let isLinked = linked.contains { SessionFolder.isSame($0.path.folderPath, summary.info.cwd) }
            return PullRequestTaskMatch.Candidate(
                id: index, link: isLinked ? reference.url : nil, isArchived: app.isArchived(summary.id),
                updatedAt: summary.info.updatedDate)
        }
        return PullRequestTaskMatch.existing(for: reference, among: candidates).map { live[$0.id] }
    }

    private func headState(of details: PullRequestDetails, in folder: URL) async -> PullRequestTaskMatch.HeadState {
        guard let checkout = try? await git.requireRepository(at: folder) else { return .current }
        let has = (try? await checkout.hasCommit(details.headRefOid)) ?? false
        let contains = has ? (try? await checkout.contains(details.headRefOid)) ?? false : false
        return PullRequestTaskMatch.headState(hasHeadCommit: has, containsHeadCommit: contains)
    }

    private func viewer(_ cli: GitHubCLI) async -> String? {
        if let login = gitHub.currentLogin { return login }
        return try? await cli.currentUser().login
    }

    /// Only asked when it decides anything: whether a maintainer may push to the author's fork.
    private func permission(
        for details: PullRequestDetails, on base: RemoteRepository, cli: GitHubCLI
    ) async -> RepositoryPermission? {
        guard details.isCrossRepository, details.maintainerCanModify,
            let wire = try? await cli.repository(.remote(base.description)).viewerPermission
        else { return nil }
        return RepositoryPermission(rawValue: wire)
    }

    // MARK: - Opening

    /// Checks the pull request out in a new worktree of the project and starts a task there,
    /// briefed on it. A head that can't be fetched (a deleted or private fork, a deleted branch)
    /// falls back to GitHub's read-only copy of it, which the brief says.
    func open(
        _ checkout: ProjectCheckout, includeReviews: Bool, progress: (Step) -> Void
    ) async throws -> SessionModel {
        let details = checkout.details
        var plan = checkout.plan
        let folder: URL
        let branch: String
        if let reusable = checkout.reusableFolder {
            folder = reusable
            let status = try? await git.requireRepository(at: reusable).status().branch
            branch = status?.name ?? plan.branch
            if status?.upstream == nil, let readOnly = plan.readOnly { plan = readOnly }
        } else {
            let repository = try await git.requireRepository(at: checkout.project.url)
            progress(.fetching)
            branch = try await repository.uniqueBranchName(plan.branch)
            do {
                try await fetch(plan, into: branch, in: repository)
            } catch let error as GitError where error.failure != .networkUnavailable {
                guard let readOnly = plan.readOnly else { throw error }
                plan = readOnly
                try await fetch(plan, into: branch, in: repository)
            }
            try await repository.setNote(Self.linkNote, details.url.absoluteString, on: branch)
            progress(.creatingWorktree)
            do {
                folder = try await git.prepareTaskCheckout(in: checkout.project.url, existingBranch: branch).folder
            } catch {
                try? await repository.deleteBranch(branch)
                throw error
            }
        }

        // Loaded before the task starts, so the brief can say when they couldn't be.
        var threads: [ReviewThread]? = []
        if includeReviews, let reference = details.reference {
            threads = try? await gitHub.cli().pullRequestPage(reference).threads
        }
        progress(.startingAgent(app.defaultAgent?.displayName ?? "the agent"))
        let session = try await app.startTask(
            in: checkout.project.id, folder: folder, title: "#\(details.number) \(details.title)")
        attach(
            PullRequestTaskBrief(
                pullRequest: details, branch: branch, pushCommand: plan.pushCommand, threads: threads,
                includesReviews: includeReviews),
            to: session)
        return session
    }

    /// Fetches the head and makes `branch` from it, tracking the head's branch when there's one
    /// to track. A remote added for a fork is taken out again if the fork can't be fetched.
    private func fetch(_ plan: PullRequestCheckoutPlan, into branch: String, in repository: Repository) async throws {
        switch plan.source {
        case .remote(let remote, let head):
            try await repository.fetch(from: remote, refspecs: [plan.fetchRefspec(into: branch)])
            try await repository.createBranch(branch, at: "refs/remotes/\(remote)/\(head)")
            try await repository.setUpstream(of: branch, remote: remote, remoteBranch: head)
        case .newRemote(let remote, let url, let head):
            try await repository.addRemote(remote, url: url)
            do {
                try await repository.fetch(from: remote, refspecs: [plan.fetchRefspec(into: branch)])
            } catch {
                try? await repository.removeRemote(remote)
                throw error
            }
            try await repository.createBranch(branch, at: "refs/remotes/\(remote)/\(head)")
            try await repository.setUpstream(of: branch, remote: remote, remoteBranch: head)
        case .pullRef(let remote, _):
            try await repository.fetch(from: remote, refspecs: [plan.fetchRefspec(into: branch)])
        }
    }

    /// The brief rides along with the task's first message as a file, like an attachment the user
    /// added; if that can't be made, it waits in the composer instead.
    private func attach(_ brief: PullRequestTaskBrief, to session: SessionModel) {
        let folder = URL.temporaryDirectory.appending(
            path: "Native Attachments/\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = folder.appending(path: brief.fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(brief.markdown.utf8).write(to: file)
            try session.attach(PromptAttachment.load(file))
        } catch {
            session.draft = brief.markdown
        }
    }

    // MARK: - An existing task

    /// Selects the task, bringing it back from the archive first.
    func show(_ task: ExistingTask) async {
        if task.isArchived {
            await app.unarchiveSession(task.key)
        }
        app.selection = task.key
    }

    /// Fast-forwards the task's branch to the pull request's head. Adds no remotes: a fork without
    /// one comes from GitHub's read-only copy. Fails, changing nothing, when the task has
    /// uncommitted changes the update would overwrite or commits the pull request doesn't.
    func update(_ task: ExistingTask) async throws {
        let checkout = try await git.requireRepository(at: task.folder)
        let remotes = try await checkout.remoteURLs().map { GitRemote(name: $0.name, url: $0.url) }
        var plan = PullRequestCheckoutPlan(task.details, remotes: remotes, viewer: nil, permission: nil)
        if case .newRemote = plan.source, let readOnly = plan.readOnly { plan = readOnly }
        do {
            try await fetchForUpdate(plan, in: checkout)
        } catch let error as GitError where error.failure != .networkUnavailable {
            guard let readOnly = plan.readOnly else { throw error }
            try await fetchForUpdate(readOnly, in: checkout)
        }
        try await checkout.fastForward(to: task.details.headRefOid)
        git.refresh(folder: task.folder)
    }

    private func fetchForUpdate(_ plan: PullRequestCheckoutPlan, in checkout: Repository) async throws {
        switch plan.source {
        case .remote(let remote, _), .newRemote(let remote, _, _):
            try await checkout.fetch(from: remote, refspecs: [plan.fetchRefspec(into: "")])
        case .pullRef(let remote, let number):
            // Into the worktree's own FETCH_HEAD: the checked-out branch can't be fetched into.
            try await checkout.fetch(from: remote, refspecs: ["refs/pull/\(number)/head"])
        }
    }

    // MARK: - Without a project

    /// Where a clone goes unless the user picks another folder: `~/Developer/<name>`. The
    /// `pullRequestTasks.cloneFolder` default moves the parent folder, so test instances never
    /// clone into the user's own.
    static func suggestedFolder(for repository: RemoteRepository) -> URL {
        let parent =
            UserDefaults.standard.string(forKey: "pullRequestTasks.cloneFolder")
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.homeDirectory.appending(path: "Developer", directoryHint: .isDirectory)
        return parent.appending(path: repository.name, directoryHint: .isDirectory)
    }

    /// What's at a folder the user might clone into.
    enum FolderState: Equatable {
        case free
        /// Already a checkout of the repository: add it rather than clone again.
        case checkout
        /// Something else is there.
        case taken
    }

    func state(of folder: URL, for repository: RemoteRepository) async -> FolderState {
        let path = folder.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .free }
        guard isDirectory.boolValue else { return .taken }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: path), contents.isEmpty {
            return .free
        }
        guard let checkout = try? await git.requireRepository(at: folder),
            SessionFolder.isSame(checkout.root.folderPath, folder.folderPath),
            let remotes = try? await checkout.remoteURLs()
        else { return .taken }
        let isClone = remotes.contains { RemoteRepository(remoteURL: $0.url)?.match(repository) != nil }
        return isClone ? .checkout : .taken
    }

    /// Clones the repository into `folder` with the user's gh (unless it's a checkout of it
    /// already) and adds it as a project.
    func addProject(_ repository: RemoteRepository, at folder: URL, progress: (Step) -> Void) async throws {
        if await state(of: folder, for: repository) != .checkout {
            progress(.cloning(repository.nameWithOwner))
            try await gitHub.cli().clone(repository, to: folder)
        }
        await app.addProject(folder)
    }
}
