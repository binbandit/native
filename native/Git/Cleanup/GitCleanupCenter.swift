import Foundation
import Git
import Observation

/// "Clean Up Merged…" for a project, from its context menu or the command palette: the sheet's
/// content while it's open, and a cleanup still running after the sheet was closed.
@Observable
final class GitCleanupCenter {
    /// The sheet's content; `nil` while it's closed.
    private(set) var presented: GitCleanupModel?
    /// The cleanup under way, which keeps going while the sheet is closed.
    @ObservationIgnored private var running: GitCleanupModel?
    @ObservationIgnored private let services: GitCleanupServices

    init(services: GitCleanupServices) {
        self.services = services
    }

    /// Opens the sheet for a project and starts looking. While a cleanup is still running, the
    /// sheet shows that one instead.
    func open(_ project: Project) {
        if let running, running.phase == .running {
            presented = running
            return
        }
        presented?.work?.cancel()
        let model = GitCleanupModel(project: project, services: services)
        // The window the user asked from, so ⌘Z there takes the cleanup back after the sheet closes.
        model.undoManager = PlatformWindow.keyUndoManager
        model.onFinished = { [weak self] in self?.finished($0) }
        presented = model
        model.work = Task { await model.scan() }
    }

    /// Closes the sheet. Looking stops; cleaning up carries on, and says how it went when done.
    func close() {
        guard let model = presented else { return }
        presented = nil
        switch model.phase {
        case .running:
            running = model
        case .finished:
            model.offerUndo()
        default:
            model.work?.cancel()
        }
    }

    func cleanUp(_ model: GitCleanupModel) {
        running = model
        model.cleanUp()
    }

    /// A run is done: without failures the sheet closes and the toast offers Undo; with them the
    /// sheet shows (again) what couldn't be done, and offers Undo when closed.
    private func finished(_ model: GitCleanupModel) {
        running = nil
        if model.failureCount == 0 {
            if presented === model { presented = nil }
            model.offerUndo()
        } else {
            presented = model
        }
    }
}
