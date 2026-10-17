import AppKit
import Observation

/// The apps a task's folder can be opened in, and the default the toolbar button opens. One shared
/// instance backs the toolbar control and the menu bar so both always agree on the default.
///
/// As in the reference app, the default is the app last chosen from the menu, so the button keeps opening
/// wherever you went last; before any choice it's the likeliest editor (`OpenInTarget.catalog`).
@Observable
final class OpenInModel {
    static let shared = OpenInModel()

    /// Installed apps in catalog order: editors, terminals, git clients, then Finder.
    private(set) var apps: [OpenInApp] = []

    var defaultApp: OpenInApp? {
        apps.first { $0.id == defaultID } ?? apps.first
    }

    private var defaultID: OpenInTarget.ID? {
        didSet { defaults.set(defaultID, forKey: Self.defaultKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var icons: [URL: NSImage] = [:]
    @ObservationIgnored private var activationObserver: Task<Void, Never>?

    private static let defaultKey = "OpenIn.defaultApp"
    /// The size macOS menus draw app icons at, as in Finder's Open With menu.
    private static let iconSize = NSSize(width: 16, height: 16)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultID = defaults.string(forKey: Self.defaultKey)
        refresh()
        // Apps come and go while Native runs; checking on activation is cheap (well under 1 ms).
        activationObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.refresh()
            }
        }
    }

    /// Looks for installed apps again.
    func refresh() {
        let installed = OpenInApp.installed()
        if installed != apps {
            apps = installed
        }
    }

    /// Opens `folder` in `app` and makes it the default.
    func open(_ folder: URL, in app: OpenInApp) {
        defaultID = app.id
        Task {
            do {
                try await app.open(folder)
            } catch {
                NSApplication.shared.presentError(error)
            }
        }
    }

    /// Opens `folder` in the default app.
    func openInDefaultApp(_ folder: URL) {
        guard let app = defaultApp else { return }
        open(folder, in: app)
    }

    /// Makes `app` the default without opening anything.
    func setDefault(_ app: OpenInApp) {
        defaultID = app.id
    }

    func copyPath(of folder: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder.path(percentEncoded: false), forType: .string)
    }

    /// The app's own icon, read from the installed bundle at menu-icon size (16pt). Native never
    /// bundles other apps' icons.
    func icon(for app: OpenInApp) -> NSImage {
        if let icon = icons[app.url] {
            return icon
        }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path(percentEncoded: false))
        icon.size = Self.iconSize
        icons[app.url] = icon
        return icon
    }
}
