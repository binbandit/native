import Foundation
import GitHub
import Observation

/// "Open as Task" for one pull request at a time: what the sheet shows from looking it up to the
/// task it opens, and the actions the sheet offers. A pull request that already has an up-to-date
/// task just selects it; anything that would change a checkout waits for the user to confirm.
@Observable
final class PullRequestTaskOpener {
    struct Request: Identifiable {
        let id = UUID()
        /// `nil` while the user picks a pull request.
        var reference: PullRequestReference?
        /// What the sheet calls it until GitHub answers.
        var title: String?
        var phase: Phase
    }

    enum Phase {
        /// Choosing a pull request, from the command palette.
        case picking
        case resolving
        /// Ready to check it out in a project, once the user confirms.
        case ready(PullRequestTaskCheckout.ProjectCheckout)
        /// A task already works on it, and the pull request has moved on since.
        case existing(PullRequestTaskCheckout.ExistingTask)
        /// No project is a checkout of its repository; clone it into `folder`.
        case needsClone(PullRequestTaskCheckout.NoProject, folder: URL, state: PullRequestTaskCheckout.FolderState?)
        case working(PullRequestTaskCheckout.Step)
        case failed(PullRequestTaskProblem)
    }

    /// The sheet's content; `nil` while it's closed.
    private(set) var request: Request?

    /// Whether the brief quotes reviews and open review comments, remembered.
    var includesReviewComments: Bool {
        didSet { defaults.set(includesReviewComments, forKey: Self.reviewCommentsKey) }
    }

    @ObservationIgnored private let checkout: PullRequestTaskCheckout
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var work: Task<Void, Never>?
    private static let reviewCommentsKey = "pullRequestTasks.includesReviewComments"

    init(checkout: PullRequestTaskCheckout, defaults: UserDefaults = .standard) {
        self.checkout = checkout
        self.defaults = defaults
        includesReviewComments = defaults.object(forKey: Self.reviewCommentsKey) as? Bool ?? true
    }

    // MARK: - Starting

    func open(_ pullRequest: PullRequestSummary) {
        guard let reference = PullRequestReference(pullRequest) else { return }
        open(reference, title: pullRequest.title)
    }

    func open(_ reference: PullRequestReference, title: String? = nil) {
        work?.cancel()
        request = Request(reference: reference, title: title, phase: .resolving)
        run { await $0.resolve(reference, rereadEnvironment: false) }
    }

    /// The command palette's "Open Pull Request as Task…": pick one first.
    func pick() {
        work?.cancel()
        request = Request(reference: nil, title: nil, phase: .picking)
    }

    /// Closes the sheet. Work under way stops only while nothing has changed yet, or mid-clone;
    /// once a checkout is being made it finishes, so nothing is left half done.
    func cancel() {
        guard canCancel else { return }
        work?.cancel()
        work = nil
        request = nil
    }

    var canCancel: Bool {
        switch request?.phase {
        case .working(let step):
            if case .cloning = step { true } else { false }
        default: true
        }
    }

    // MARK: - The sheet's actions

    /// The primary button: open, update, or clone, as the phase offers.
    func confirm() {
        switch request?.phase {
        case .ready(let checkout):
            run { await $0.open(checkout) }
        case .existing(let task):
            run { await $0.update(task) }
        case .needsClone(let missing, let folder, let state) where state == .free || state == .checkout:
            run { await $0.clone(missing, into: folder) }
        default:
            break
        }
    }

    /// Opens the existing task without bringing the pull request's new commits in.
    func openWithoutUpdating() {
        guard case .existing(let task) = request?.phase else { return }
        show(task)
    }

    func perform(_ action: PullRequestTaskProblem.Action) {
        switch action {
        case .retry:
            guard let reference = request?.reference else { return }
            run { await $0.resolve(reference, rereadEnvironment: true) }
        case .openTask(let task):
            show(task)
        case .chooseFolder:
            guard let reference = request?.reference else { return }
            run { await $0.resolve(reference, rereadEnvironment: false) }
        }
    }

    /// The folder picked to clone into: the folder itself when it's empty or a checkout of the
    /// repository, otherwise a folder named after the repository inside it.
    func chooseCloneFolder(_ picked: URL) {
        guard case .needsClone(let missing, _, _) = request?.phase else { return }
        run { opener in
            var folder = picked
            if await opener.checkout.state(of: picked, for: missing.repository) == .taken {
                folder = picked.appending(path: missing.repository.name, directoryHint: .isDirectory)
            }
            await opener.inspect(folder, for: missing)
        }
    }

    // MARK: - Steps

    private func resolve(_ reference: PullRequestReference, rereadEnvironment: Bool) async {
        setPhase(.resolving)
        do {
            switch try await checkout.resolve(reference, rereadEnvironment: rereadEnvironment) {
            case .existing(let task) where task.headState == .current:
                show(task)
            case .existing(let task):
                request?.title = task.details.title
                setPhase(.existing(task))
            case .checkout(let checkout):
                request?.title = checkout.details.title
                setPhase(.ready(checkout))
            case .noProject(let missing):
                request?.title = missing.details.title
                await inspect(PullRequestTaskCheckout.suggestedFolder(for: missing.repository), for: missing)
            }
        } catch {
            fail(error, .lookingUp(reference))
        }
    }

    private func inspect(_ folder: URL, for missing: PullRequestTaskCheckout.NoProject) async {
        setPhase(.needsClone(missing, folder: folder, state: nil))
        let state = await checkout.state(of: folder, for: missing.repository)
        guard !Task.isCancelled else { return }
        setPhase(.needsClone(missing, folder: folder, state: state))
    }

    private func open(_ project: PullRequestTaskCheckout.ProjectCheckout) async {
        var stage = PullRequestTaskProblem.Stage.checkingOut(project.details)
        do {
            _ = try await checkout.open(project, includeReviews: includesReviewComments) { step in
                if case .startingAgent = step { stage = .starting(project.details) }
                setPhase(.working(step))
            }
            request = nil
        } catch {
            fail(error, stage)
        }
    }

    private func update(_ task: PullRequestTaskCheckout.ExistingTask) async {
        setPhase(.working(.updating))
        do {
            try await checkout.update(task)
            show(task)
        } catch {
            fail(error, .updating(task))
        }
    }

    /// Clones (or adds the checkout already there), then carries on: the user confirmed opening
    /// the pull request along with the clone.
    private func clone(_ missing: PullRequestTaskCheckout.NoProject, into folder: URL) async {
        do {
            try await checkout.addProject(missing.repository, at: folder) { setPhase(.working($0)) }
        } catch {
            fail(error, .cloning(missing.repository))
            return
        }
        guard let reference = request?.reference else { return }
        setPhase(.working(.lookingUp))
        do {
            switch try await checkout.resolve(reference) {
            case .checkout(let project): await open(project)
            case .existing(let task): show(task)
            case .noProject:
                // The clone's remotes don't name the repository (an `insteadOf` rewrite, say).
                fail(PullRequestTaskOpenerError.cloneNotMatched(folder), .cloning(missing.repository))
            }
        } catch {
            fail(error, .lookingUp(reference))
        }
    }

    private func show(_ task: PullRequestTaskCheckout.ExistingTask) {
        request = nil
        Task { await checkout.show(task) }
    }

    // MARK: - Helpers

    /// Runs one step at a time; a new one replaces whatever was under way.
    private func run(_ body: @escaping @MainActor (PullRequestTaskOpener) async -> Void) {
        work?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            await body(self)
        }
    }

    private func setPhase(_ phase: Phase) {
        guard !Task.isCancelled else { return }
        request?.phase = phase
    }

    private func fail(_ error: any Error, _ stage: PullRequestTaskProblem.Stage) {
        guard !Task.isCancelled, !(error is CancellationError), (error as? GitHubError) != .cancelled else { return }
        setPhase(.failed(PullRequestTaskProblem(error, during: stage)))
    }
}

enum PullRequestTaskOpenerError: LocalizedError {
    case cloneNotMatched(URL)

    var errorDescription: String? {
        switch self {
        case .cloneNotMatched(let folder):
            "It was cloned to \(folder.path(percentEncoded: false)) and added as a project, but none of its remotes names the repository, so Native can't tell it's the right one."
        }
    }
}
