import Foundation
import Observation
import SwiftUI

/// The apps a folder can be opened in, and the default the button opens. One shared instance backs
/// the toolbar control and the menu bar, so both always agree on the default.
///
/// The default is the app last chosen from the menu, so the button keeps opening
/// wherever you went last; before any choice it's the likeliest editor (`OpenInTarget.catalog`).
@Observable
final class OpenInModel {
    static let shared = OpenInModel()

    /// Installed apps in catalog order: editors, terminals, git clients, then Finder.
    private(set) var apps: [OpenInApp] = []
    /// The location whose path was just copied, for a moment, so the control can confirm it.
    private(set) var copiedLocation: OpenInLocation?

    private var defaultID: OpenInTarget.ID? {
        didSet { defaults.set(defaultID, forKey: Self.defaultKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var activationObserver: Task<Void, Never>?
    @ObservationIgnored private var copiedReset: Task<Void, Never>?

    private static let defaultKey = "OpenIn.defaultApp"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultID = defaults.string(forKey: Self.defaultKey)
        refresh()
        // Apps come and go while Native runs; looking again is cheap (well under 1 ms).
        activationObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: OpenInPlatform.didBecomeActive) {
                self?.refresh()
            }
        }
    }

    /// The apps that can open the location.
    func apps(for location: OpenInLocation) -> [OpenInApp] {
        apps.filter { $0.canOpen(location) }
    }

    /// What the button opens the location in: the default, or the likeliest app that can open it.
    func defaultApp(for location: OpenInLocation) -> OpenInApp? {
        let apps = apps(for: location)
        return apps.first { $0.id == defaultID } ?? apps.first
    }

    /// `apps(for:)` split into editors, terminals, git clients and Finder: the menus' sections.
    func appGroups(for location: OpenInLocation) -> [[OpenInApp]] {
        apps(for: location).reduce(into: []) { groups, app in
            if groups.last?.last?.target.kind == app.target.kind {
                groups[groups.count - 1].append(app)
            } else {
                groups.append([app])
            }
        }
    }

    func icon(for app: OpenInApp) -> Image {
        OpenInPlatform.icon(for: app)
    }

    /// Looks for installed apps again.
    func refresh() {
        let installed = OpenInPlatform.installedApps()
        if installed != apps {
            apps = installed
        }
    }

    /// Opens the location in `app` and makes it the default.
    func open(_ location: OpenInLocation, in app: OpenInApp) {
        defaultID = app.id
        Task {
            do {
                try await OpenInPlatform.open(location, in: app)
            } catch {
                OpenInPlatform.present(error)
            }
        }
    }

    /// The button's action: opens the location in the default app, or copies its path when no app
    /// can open it (a remote folder and no remote-capable editor, or an iPad).
    func openInDefaultApp(_ location: OpenInLocation) {
        if let app = defaultApp(for: location) {
            open(location, in: app)
        } else {
            copyPath(of: location)
        }
    }

    func copyPath(of location: OpenInLocation) {
        DSPasteboard.copy(location.path)
        copiedLocation = location
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.dsStandard) { self?.copiedLocation = nil }
        }
    }
}
