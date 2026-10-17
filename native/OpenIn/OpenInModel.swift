import AppKit
import Observation

/// The apps a task's folder can be opened in, and the default the toolbar button opens. One shared
/// instance backs the toolbar control and the menu bar so both always agree on the default.
///
/// As in Conductor, the default is the app last chosen from the menu, so the button keeps opening
/// wherever you went last; before any choice it's the likeliest editor (`OpenInTarget.catalog`).
@Observable
final class OpenInModel {
    static let shared = OpenInModel()

    /// Installed apps in catalog order: editors, terminals, git clients, then Finder.
    private(set) var apps: [OpenInApp] = []

    var defaultApp: OpenInApp? {
        apps.first { $0.id == defaultID } ?? apps.first
    }

    /// `apps` split into editors, terminals, git clients and Finder: the sections of the menus.
    var appGroups: [[OpenInApp]] {
        apps.reduce(into: []) { groups, app in
            if groups.last?.last?.target.kind == app.target.kind {
                groups[groups.count - 1].append(app)
            } else {
                groups.append([app])
            }
        }
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

    /// Opens the location in `app` and makes it the default.
    func open(_ location: OpenInLocation, in app: OpenInApp) {
        defaultID = app.id
        Task {
            do {
                try await app.open(location)
            } catch {
                NSApplication.shared.presentError(error)
            }
        }
    }

    /// Opens the location in the default app.
    func openInDefaultApp(_ location: OpenInLocation) {
        guard let app = defaultApp else { return }
        open(location, in: app)
    }

    /// Makes `app` the default without opening anything.
    func setDefault(_ app: OpenInApp) {
        defaultID = app.id
    }

    func copyPath(of location: OpenInLocation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(location.path, forType: .string)
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
