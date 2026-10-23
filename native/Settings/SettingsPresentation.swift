import Foundation
import NativeTelemetry
import Observation

/// Whether Settings has taken over the main window, and on which page. Settings is part of the
/// window, so everything that opens it (⌘,, the sidebar's gear, a feature linking
/// to its page) sets `pane`, and leaving it (Back, Escape, ⌘[) clears it.
@Observable
final class SettingsPresentation {
    struct ProjectScope: Equatable {
        let pane: SettingsPane.ID
        let project: URL
    }

    /// The project a page that can show one project's switches (MCP Servers, Skills) opens on, set
    /// when a project's settings link there. The page takes it once it appears.
    private(set) var projectScope: ProjectScope?

    /// The page shown; nil while Settings is closed.
    var pane: SettingsPane.ID? {
        didSet {
            if let projectScope, projectScope.pane != pane { self.projectScope = nil }
            if oldValue == nil, pane != nil {
                Telemetry.record(.featureUsed(.settings))
            }
        }
    }

    var isShown: Bool { pane != nil }

    func open(_ pane: SettingsPane.ID = .general) {
        projectScope = nil
        self.pane = pane
    }

    /// Opens `pane` on `project`'s switches.
    func open(_ pane: SettingsPane.ID, scopedTo project: URL) {
        projectScope = ProjectScope(pane: pane, project: project)
        self.pane = pane
    }

    /// The project a page should open on, once: later visits show every project again.
    func takeProjectScope(for pane: SettingsPane.ID) -> URL? {
        guard projectScope?.pane == pane else { return nil }
        defer { projectScope = nil }
        return projectScope?.project
    }

    func close() {
        pane = nil
        projectScope = nil
    }

    /// ⌘,: opens General, or closes Settings if it's already open.
    func toggle() {
        pane = pane == nil ? .general : nil
    }
}
