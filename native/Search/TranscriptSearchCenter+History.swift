import Foundation
import Search

// Past sessions: passes over the agents' own history, what Native knows about the sessions they
// read, and how far they've got.
extension TranscriptSearchCenter {
    func startBackfill() {
        guard isEnabled, includesAgentHistory, let index, let model else { return }
        guard backfillTask == nil else {
            needsAnotherPass = true
            return
        }
        let readers = model.plugins.historyReaders.map {
            TranscriptSearchBackfill.Reader(agent: $0.agent.rawValue, reader: $0.reader)
        }
        let backfill = TranscriptSearchBackfill(
            index: index, readers: readers, known: { [weak self] in await self?.known($0) }, projects: projectFolders,
            excluded: excludedFolders, retainedSince: retainedSince)
        lastBackfill = .now
        needsAnotherPass = false
        let id = UUID()
        backfillID = id
        backfillTask = Task(priority: .utility) { [weak self] in
            // The first fill runs at utility priority so search is useful soon; once the index
            // exists, catching up runs at background priority (and either waits on battery).
            let isFirstFill = await (try? index.isFilled()) == false
            let priority: TaskPriority =
                isFirstFill && !PlatformPowerSource.prefersSavingEnergy ? .utility : .background
            let pass = Task(priority: priority) {
                await backfill.run { [weak self] state in
                    await self?.update(indexing: state)
                }
            }
            let finished = await withTaskCancellationHandler {
                await pass.value
            } onCancel: {
                pass.cancel()
            }
            if finished {
                try? await index.markFilled()
            }
            self?.backfillFinished(id)
        }
    }

    private func backfillFinished(_ id: UUID) {
        // A pass that was stopped and replaced finishes after its replacement started.
        guard id == backfillID else { return }
        backfillTask = nil
        lastBackfill = .now
        if needsAnotherPass {
            startBackfill()
        }
    }

    /// A pass a moment from now, so several turns ending together read their logs once.
    func scheduleBackfill() {
        pendingBackfill?.cancel()
        pendingBackfill = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.startBackfill()
        }
    }

    /// What the sidebar knows about a session the backfill read: its title, project and whether
    /// it's archived.
    private func known(_ key: SearchSessionKey) -> TranscriptSearchBackfill.Known? {
        guard let model else { return nil }
        let sessionKey = SessionKey(searchKey: key)
        guard let (projectID, info) = model.catalog.lookup(sessionKey), let project = model.projects.project(projectID),
            let agent = model.plugins.agent(sessionKey.agent)
        else { return nil }
        let summary = SessionSummary(project: projectID, agent: agent, info: info)
        return TranscriptSearchBackfill.Known(
            title: model.title(for: summary), project: project.path, isArchived: model.isArchived(sessionKey))
    }

    func stopBackfill() {
        backfillTask?.cancel()
        backfillTask = nil
        indexing = .idle
    }

    private func update(indexing state: TranscriptSearchIndexing) async {
        indexing = state
        // Progress comes per file; counts and results refresh at most once a second.
        guard state == .idle || Date.now.timeIntervalSince(lastRefresh) > 1 else { return }
        lastRefresh = .now
        await refreshStatistics()
        // New sessions land while the panel is open: show them without the user retyping.
        if isPresented {
            scheduleSearch(debounce: false)
        }
    }

    private func refreshStatistics() async {
        statistics = try? await index?.statistics()
    }
}
