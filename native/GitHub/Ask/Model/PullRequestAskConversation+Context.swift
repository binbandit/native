import Foundation
import GitHub

// The pull request's context for the agent: loaded through the page's own model (so the page and
// the panel share one copy and one set of gh calls), cut to a budget by `PullRequestAskContext`,
// and saved in the conversation's folder for the agent to read what didn't fit.
extension PullRequestAskConversation {
    /// Patches come a hundred files to a page; past this many pages the rest are named, not loaded.
    static let patchPageLimit = 10
    /// Conversation items come a hundred to a page, after the page's first hundred.
    static let extraTimelinePages = 2

    /// The pull request as it is now, loading what the page hasn't yet.
    func gatherContext() async throws -> (PullRequestAskSource, PullRequestAskContext) {
        guard let gitHub = center.gitHub else { throw PullRequestAskFailure.gitHub(.cancelled) }
        let model = gitHub.pageModel(for: reference)
        guard let page = await currentPage() else {
            throw PullRequestAskFailure.gitHub(model.loadError ?? .notFound("\(reference.display) didn't load."))
        }
        await model.loadAllFiles()
        await loadPatches(of: model)
        for _ in 0..<Self.extraTimelinePages where model.page?.timelineCursor != nil {
            await model.loadMoreTimeline()
        }
        let source = PullRequestAskSource(page: model.page ?? page, files: model.files, patches: model.patches)
        // Cutting thousands of diffs to a budget is string work; keep it off the main thread.
        let context = await Self.context(for: source)
        return (source, context)
    }

    /// The page, loaded if it wasn't and refreshed if it's stale.
    func currentPage() async -> PullRequestPage? {
        guard let model = center.gitHub?.pageModel(for: reference) else { return nil }
        await model.loadIfStale()
        return model.page
    }

    /// Loads patch pages until every file has one or the limit is reached, waiting out a page the
    /// Files Changed tab is already fetching.
    private func loadPatches(of model: PullRequestPageModel) async {
        var loaded = 0
        while !model.patchesComplete, loaded < Self.patchPageLimit, !Task.isCancelled {
            if model.isLoadingPatches {
                try? await Task.sleep(for: .milliseconds(150))
                continue
            }
            let before = model.patchPagesLoaded
            await model.loadNextPatchPage()
            // A failed page (offline, say) ends it; the files without patches say so.
            guard model.patchPagesLoaded > before else { return }
            loaded += 1
        }
    }

    @concurrent nonisolated private static func context(for source: PullRequestAskSource) async -> PullRequestAskContext
    {
        PullRequestAskContext(source)
    }

    // MARK: - The folder

    /// Writes the saved copy into `folder`, replacing an older one.
    func save(_ context: PullRequestAskContext, to folder: URL) async throws {
        do {
            try await Self.write(context.workspace, to: folder)
        } catch {
            throw PullRequestAskFailure.workspace(error.localizedDescription)
        }
    }

    func ensureFolder(_ folder: URL) async throws {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw PullRequestAskFailure.workspace(error.localizedDescription)
        }
    }

    @concurrent nonisolated private static func write(
        _ files: [PullRequestAskWorkspaceFile], to folder: URL
    ) async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Diffs of files the pull request no longer changes mustn't linger.
        let diffs = folder.appending(path: "diff", directoryHint: .isDirectory)
        if manager.fileExists(atPath: diffs.path(percentEncoded: false)) {
            try manager.removeItem(at: diffs)
        }
        for file in files {
            let url = folder.appending(path: file.path, directoryHint: .notDirectory)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: url, options: .atomic)
        }
    }
}
