import Foundation
import NativePolicy
import Observation
import TaskList
import Undo

/// One folder action owns its progress and persistent receipt. It never borrows a task's draft.
@Observable
final class SidebarFoldersModel {
    struct Receipt {
        let id = UUID()
        let projects: [Project]
        let previousProject: Project.ID?
        let previousSelection: SessionKey?
        var action: UndoableAction?
    }

    struct Failure: Equatable {
        let name: String
        let reason: String
        var message: String {
            if name.isEmpty || reason.hasPrefix("Can’t") || reason.hasPrefix("Native") { return reason }
            return "\(name). \(reason)"
        }
    }

    private(set) var history: FolderHistory
    var opening: [String] = []
    var receipt: Receipt?
    var failures: [Failure] = []
    var hovered: [String] = []
    var dropRequest: UUID?
    var acceptsDrop = false
    var focusRequests = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var policyOverride: NativePolicy?
    @ObservationIgnored var access: [URL] = []
    private static let historyKey = "sidebarFolders.localHistory"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        history =
            defaults.data(forKey: Self.historyKey).flatMap { try? JSONDecoder().decode(FolderHistory.self, from: $0) }
            ?? FolderHistory()
    }

    deinit {
        for url in access { url.stopAccessingSecurityScopedResource() }
    }

    func remember(_ url: URL) {
        history.opened(url, bookmark: PlatformFolderAccess.bookmark(url))
        saveHistory()
    }

    func clearHistory() {
        history.clear()
        saveHistory()
    }

    func dismissResult() {
        receipt = nil
        failures = []
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: Self.historyKey) }
    }
}
