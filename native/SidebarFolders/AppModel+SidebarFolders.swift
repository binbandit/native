import Experiments
import Foundation
import NativePolicy
import TaskList
import Undo

extension AppModel {
    var offersSidebarFolders: Bool { experiments.value(of: .sidebarNext) }
    var folderPolicy: NativePolicy { sidebarFolders.policyOverride ?? PolicyCenter.shared.policy }
    var canOpenFolders: Bool { folderPolicy.decision(for: .folderAdd).isPermitted }

    func canOpenRecentFolder(_ entry: FolderHistory.Entry) -> Bool {
        let policy = folderPolicy
        let roots = policy.foldersAllowedRoots?.map {
            URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        return policy.allowsFolder(entry.url.path, canonicalRoots: roots)
    }

    /// Every visible entry point, including Command-O, uses the same admission and chooser.
    func requestOpenFolder() {
        guard canOpenFolders, sidebarFolders.opening.isEmpty else { return }
        isAddingProject = true
    }

    /// Legacy and Quick Entry additions consult the same managed roots even with Labs off.
    /// With no folder restriction, their shipped behavior stays unchanged.
    func admittedProjectFolder(_ url: URL) async -> URL? {
        guard folderPolicy.foldersAllowedRoots != nil || !canOpenFolders else { return url }
        let resolved = await PlatformFolderAccess.inspect([url], policy: folderPolicy)
        guard let item = resolved.first, item.failure == nil else {
            actionFailure = ActionFailure(
                "Can’t Open Folder",
                resolved.first?.failure?.message(for: url.lastPathComponent)
                    ?? "Only approved folders can be added.")
            return nil
        }
        // Policy may have changed while access was being resolved.
        let roots = folderPolicy.foldersAllowedRoots?.map {
            URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        guard folderPolicy.allowsFolder(item.url.path, canonicalRoots: roots) else {
            if item.hasSecurityScope { item.original.stopAccessingSecurityScopedResource() }
            actionFailure = ActionFailure("Can’t Open Folder", "Only approved folders can be added.")
            return nil
        }
        if item.hasSecurityScope { sidebarFolders.access.append(item.original) }
        return item.url
    }

    func openRecentFolder(_ entry: FolderHistory.Entry, undoManager: UndoManager?) async {
        do {
            let url = try entry.bookmark.map(PlatformFolderAccess.resolve) ?? entry.url
            await openSidebarFolders([url], undoManager: undoManager)
        } catch {
            sidebarFolders.dismissResult()
            sidebarFolders.failures = [
                .init(name: "Can’t open \(entry.url.lastPathComponent)", reason: "Folder access expired.")
            ]
        }
    }

    /// Resolves the complete batch before adding anything. A second action cannot interleave with it.
    func openSidebarFolders(_ urls: [URL], undoManager: UndoManager?) async {
        guard sidebarFolders.opening.isEmpty else { return }
        guard !urls.isEmpty else {
            sidebarFolders.dismissResult()
            sidebarFolders.failures = [.init(name: "", reason: "Choose a folder to add a project.")]
            return
        }
        sidebarFolders.dismissResult()
        sidebarFolders.opening = urls.map(\.lastPathComponent)
        defer { sidebarFolders.opening = [] }
        let resolved = await PlatformFolderAccess.inspect(urls, policy: folderPolicy)
        let added = finishOpeningFolders(resolved, undoManager: undoManager)
        // Existing task drafts stay in their sessions; opening a folder only lists saved sessions.
        for runtime in agents where !added.isEmpty && runtime.status == .idle {
            Task { await ensureRunning(runtime.agent.id) }
        }
        for project in added where projects.project(project.id) != nil { await refreshSessions(in: project) }
    }

    /// A synchronous commit rechecks live policy after asynchronous access resolution.
    @discardableResult
    func finishOpeningFolders(_ resolved: [PlatformFolderAccess.Resolved], undoManager: UndoManager?) -> [Project] {
        let previousProject = focusedProjectID
        let previousSelection = selection
        let existing = Set(projects.all.map(\.id))
        let policy = folderPolicy
        let roots = policy.foldersAllowedRoots?.map {
            URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        var opened: [Project] = []
        for item in resolved {
            let failure =
                item.failure
                ?? (policy.allowsFolder(item.url.path, canonicalRoots: roots)
                    ? nil : .notAllowed)
            if let failure {
                sidebarFolders.failures.append(
                    .init(
                        name: item.original.lastPathComponent,
                        reason: failure.message(for: item.original.lastPathComponent),
                        needsLocation: failure == .missing))
                if item.hasSecurityScope { item.original.stopAccessingSecurityScopedResource() }
                continue
            }
            if item.hasSecurityScope {
                if sidebarFolders.access.contains(item.original) {
                    item.original.stopAccessingSecurityScopedResource()
                } else {
                    sidebarFolders.access.append(item.original)
                }
            }
            let project = projects.add(item.url)
            if !opened.contains(where: { $0.id == project.id }) { opened.append(project) }
            sidebarFolders.remember(item.url)
        }
        let added = opened.filter { !existing.contains($0.id) }
        if let first = (added.first ?? opened.first) {
            focusProject(first.id)
            sidebarFolders.focusRequests &+= 1
            homeNext.startFieldFocusRequests &+= 1
        }
        if !added.isEmpty {
            let receipt = SidebarFoldersModel.Receipt(
                projects: added, previousProject: previousProject, previousSelection: previousSelection)
            var offered = receipt
            offered.action = undoable(
                added.count == 1 ? "Added \(added[0].name)." : "Added \(added.count) folders.",
                name: added.count == 1 ? "Add Folder" : "Add Folders", undoManager: undoManager,
                undo: { model in model.undoFolderAddition(receipt) }, redo: nil)
            sidebarFolders.receipt = offered
        }
        return added
    }

    func undoOfferedFolderAddition(_ receipt: SidebarFoldersModel.Receipt) {
        if let action = receipt.action { action.undo() } else { undoFolderAddition(receipt) }
    }

    func undoFolderAddition(_ receipt: SidebarFoldersModel.Receipt) {
        let ids = Set(receipt.projects.map(\.id))
        let wasShowingAddition = selection == nil && focusedProjectID.map(ids.contains) == true
        for project in receipt.projects { removeProject(project.id) }
        if wasShowingAddition {
            focusedProjectID = receipt.previousProject.flatMap { projects.project($0)?.id }
            selection = receipt.previousSelection
        }
        if sidebarFolders.receipt?.id == receipt.id { sidebarFolders.receipt = nil }
    }

    func dismissFolderResult() { sidebarFolders.dismissResult() }
    func clearRecentFolders() { sidebarFolders.clearHistory() }

    func folderPickerFinished(_ result: Result<URL?, any Error>, undoManager: UndoManager?) {
        switch result {
        case .success(let url?): Task { await openSidebarFolders([url], undoManager: undoManager) }
        case .success(nil): break
        case .failure(let error) where (error as? CocoaError)?.code == .userCancelled: break
        case .failure:
            sidebarFolders.dismissResult()
            sidebarFolders.failures = [.init(name: "", reason: "Can’t open this folder. Choose Folder…")]
        }
    }
}
