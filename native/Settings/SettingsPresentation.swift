import NativeTelemetry
import Observation

/// Whether Settings has taken over the main window, and on which page. Settings is part of the
/// window, so everything that opens it (⌘,, the sidebar's gear, a feature linking
/// to its page) sets `pane`, and leaving it (Back, Escape, ⌘[) clears it.
@Observable
final class SettingsPresentation {
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

    func close() {
        pane = nil
    }

    /// ⌘,: opens General, or closes Settings if it's already open.
    func toggle() {
        pane = pane == nil ? .general : nil
    }
}
