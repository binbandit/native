import Foundation
import NativeTelemetry
import Observation

/// Whether Settings has taken over the main window, and on which page. Settings is part of the
/// window, so everything that opens it (⌘,, the sidebar's gear, a feature linking
/// to its page) sets `pane`, and leaving it (Back, Escape, ⌘[) clears it.
@Observable
final class SettingsPresentation {
    /// The project a page that can show one project's switches (MCP Servers, Skills) opens on, set
    /// when a project's settings link there. The page takes it once it appears.
    @ObservationIgnored var projectScope: URL?

    /// The page shown; nil while Settings is closed.
    var pane: SettingsPane.ID? {
        didSet {
            if oldValue == nil, pane != nil {
                Telemetry.record(.featureUsed(.settings))
            }
        }
    }

    var isShown: Bool { pane != nil }

    func open(_ pane: SettingsPane.ID = .general) {
        self.pane = pane
    }

    /// Opens `pane` on `project`'s switches.
    func open(_ pane: SettingsPane.ID, scopedTo project: URL) {
        projectScope = project
        self.pane = pane
    }

    /// The project a page should open on, once: later visits show every project again.
    func takeProjectScope() -> URL? {
        defer { projectScope = nil }
        return projectScope
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
