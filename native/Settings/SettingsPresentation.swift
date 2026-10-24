import AppAppearance
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

    private(set) var requestedRow: SettingsReveal?

    /// The page shown; nil while Settings is closed.
    var pane: SettingsPane.ID? {
        didSet {
            if oldValue != pane { requestedRow = nil }
            if let projectScope, projectScope.pane != pane { self.projectScope = nil }
            if pane != oldValue { dismissDetail() }
            if oldValue == nil, pane != nil {
                Telemetry.record(.featureUsed(.settings))
            }
        }
    }

    /// A page can push a local detail without replacing Settings or losing its scroll position.
    @ObservationIgnored private var detailBack: (() -> Void)?
    @ObservationIgnored private var detailScroll = SettingsDetailScrollState()
    @ObservationIgnored var pageOffset: Double = 0
    @ObservationIgnored var scrollPage: ((Double) -> Void)?

    func showDetail(_ id: String?, back: (() -> Void)? = nil) {
        if id != nil {
            detailScroll.openDetail(at: pageOffset)
            detailBack = back
        } else if detailBack != nil {
            detailBack = nil
            detailScroll.returnToList()
        }
    }

    func detailListDidLayout() {
        guard let offset = detailScroll.listDidLayout() else { return }
        scrollPage?(offset)
    }

    /// A search result owns its destination; returning to the old list offset would override it.
    func dismissDetail() {
        let back = detailBack
        detailScroll.discard()
        detailBack = nil
        back?()
    }

    func goBack() {
        if let back = detailBack {
            showDetail(nil)
            back()
        } else {
            close()
        }
    }

    var isShown: Bool { pane != nil }

    func open(_ pane: SettingsPane.ID = .general) {
        requestedRow = nil
        projectScope = nil
        self.pane = pane
    }

    /// Opens a setting by the same reveal target search uses.
    func open(_ pane: SettingsPane.ID, revealing row: SettingsRowID) {
        open(pane)
        requestedRow = SettingsReveal(rowID: row)
    }

    func takeRequestedRow() -> SettingsReveal? {
        defer { requestedRow = nil }
        return requestedRow
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
        detailScroll.discard()
        detailBack = nil
        pane = nil
        projectScope = nil
    }

    /// ⌘,: opens General, or closes Settings if it's already open.
    func toggle() {
        pane = pane == nil ? .general : nil
    }
}
