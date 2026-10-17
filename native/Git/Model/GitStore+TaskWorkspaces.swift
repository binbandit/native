import Foundation
import Git

/// New tasks' checkouts: a worktree (or a branch in the project's checkout) on a provisional
/// branch, set up from the project, then renamed after the task's title.
extension GitStore {
    /// How long a setup script may run before it's stopped.
    static let setupTimeout = Duration.seconds(15 * 60)

    /// Makes the checkout a new task runs in, following `settings`. A worktree gets the project's
    /// ignored env files before this returns, so the agent sees them from its first turn, and its
    /// setup script starts in the background. `nil` when the project isn't a git repository.
    func prepareTaskCheckout(in project: URL, prefix: String) async throws -> GitTaskCheckout? {
        guard let repository = try await resolveGit().repository(at: project) else { return nil }
        let (branch, code) = try await provisionalBranch(in: repository, prefix: prefix)
        switch settings.newTaskWorkspace {
        case .branch:
            try await repository.createAndSwitchBranch(branch)
            try await repository.markProvisional(branch)
            model(for: repository.root).refresh()
            return GitTaskCheckout(folder: repository.root, branch: branch, copiedFiles: [], runsSetupScript: false)
        case .worktree:
            let main = try await repository.worktrees().first(where: \.isMain)?.path ?? repository.root
            let folder = Worktree.defaultLocation(home: repository.git.environment["HOME"])
                .appending(path: Worktree.slug(repository.name, maxLength: 60), directoryHint: .isDirectory)
                .appending(path: code, directoryHint: .isDirectory)
            let worktree = try await repository.addWorktree(at: folder, newBranch: branch)
            try await repository.markProvisional(branch)
            var run = GitSetupRun(state: .running, copiedFiles: [], projectRoot: main)
            do {
                run.copiedFiles = try await requireRepository(at: main).copyIgnoredFiles(
                    matching: settings.envFilePatterns, to: worktree.path)
            } catch {
                run.copyFailure = error.localizedDescription
            }
            let script = settings.setupScript(forProjectAt: main)
            let key = worktree.path.standardizedFileURL
            if let script {
                setupRuns[key] = run
                startSetup(script, in: worktree.path, branch: branch, run: run)
            } else if run.copyFailure != nil {
                run.state = .failed("Couldn't copy the project's env files.")
                setupRuns[key] = run
            }
            return GitTaskCheckout(
                folder: worktree.path, branch: branch, copiedFiles: run.copiedFiles, runsSetupScript: script != nil)
        }
    }

    /// Runs the project's setup script in a task worktree again, e.g. after fixing it.
    func retrySetup(in folder: URL) {
        let key = folder.standardizedFileURL
        guard var run = setupRuns[key] else { return }
        guard let script = settings.setupScript(forProjectAt: run.projectRoot) else {
            setupRuns[key] = nil
            return
        }
        run.state = .running
        setupRuns[key] = run
        startSetup(script, in: folder, branch: model(for: folder).branch?.name, run: run)
    }

    func dismissSetup(in folder: URL) {
        setupRuns[folder.standardizedFileURL] = nil
    }

    /// Renames a task's provisional branch after its title, if the settings allow it and the
    /// branch hasn't been renamed or pushed. Generic titles ("New Session") are skipped.
    func renameProvisionalBranch(at folder: URL, title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.renamesBranches, !title.isEmpty, title != "New Session" else { return }
        let model = model(for: folder)
        if model.repository == nil { await model.refreshNow() }
        guard let repository = model.repository, let branch = model.branch?.name else { return }
        if (try? await repository.renameProvisionalBranch(branch, title: title)) != nil {
            model.refresh()
        }
    }

    // MARK: - Helpers

    /// `<prefix><code>` with a code no branch uses yet.
    private func provisionalBranch(in repository: Repository, prefix: String) async throws -> (String, String) {
        for _ in 0..<5 {
            let code = BranchNaming.provisionalCode()
            let branch = prefix + code
            if try await repository.uniqueBranchName(branch) == branch { return (branch, code) }
        }
        throw GitError.failed(arguments: ["branch"], status: 1, stderr: "Couldn't find a free branch name.")
    }

    private func startSetup(_ script: String, in folder: URL, branch: String?, run: GitSetupRun) {
        let key = folder.standardizedFileURL
        Task {
            var run = run
            do {
                let repository = try await requireRepository(at: folder)
                let result = try await repository.runSetupScript(
                    script,
                    environment: [
                        "NATIVE_WORKSPACE_PATH": folder.path(percentEncoded: false),
                        "NATIVE_ROOT_PATH": run.projectRoot.path(percentEncoded: false),
                        "NATIVE_BRANCH": branch ?? "",
                    ],
                    timeout: Self.setupTimeout
                )
                run.state = .finished(result)
            } catch {
                run.state = .failed(error.localizedDescription)
            }
            // A dismissed or removed run stays gone.
            if setupRuns[key] != nil { setupRuns[key] = run }
            model(for: folder).refresh()
        }
    }
}
