import Foundation
import Observation

/// Decides when What's New appears and remembers what was seen. It shows once per version, on the
/// first launch after updating to a version with highlights (collecting any skipped versions),
/// never on a brand-new install, and only when nothing needs the user (`presentIfReady`).
@Observable
final class WhatsNewCenter {
    /// What the sheet shows; nil while it's closed.
    var presented: [WhatsNewRelease]?

    /// Releases waiting for a moment when nothing needs the user.
    private(set) var pending: [WhatsNewRelease] = []
    let current: WhatsNewVersion

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let catalog: [WhatsNewRelease]

    static let enabledKey = "whatsNew.enabled"
    static let lastSeenKey = "whatsNew.lastSeenVersion"
    /// Simulates an update: launch with `-whatsNewVersionOverride 0.3.0 -whatsNew.lastSeenVersion 0.1.0`.
    static let versionOverrideKey = "whatsNewVersionOverride"

    init(
        version: String = AppVersion.current.version, catalog: [WhatsNewRelease] = WhatsNewCatalog.releases,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.catalog = catalog
        current = WhatsNewVersion(defaults.string(forKey: Self.versionOverrideKey) ?? version)
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// Call once at launch: works out what's new since the last launch and records this version.
    func start() {
        let lastSeen = defaults.string(forKey: Self.lastSeenKey).map(WhatsNewVersion.init)
        pending = isEnabled ? WhatsNewSchedule.pending(in: catalog, lastSeen: lastSeen, current: current) : []
        if pending.isEmpty, lastSeen.map({ $0 < current }) ?? true {
            // A new install, an update with nothing to show, or the sheet turned off.
            defaults.set(current.description, forKey: Self.lastSeenKey)
        }
    }

    /// Shows the pending highlights, unless something needs the user; call again once it doesn't.
    func presentIfReady(blocked: Bool) {
        guard !blocked, presented == nil, !pending.isEmpty else { return }
        presented = pending
    }

    /// Help ▸ What's New: the newest highlights up to this version, any time.
    func show() {
        presented = WhatsNewSchedule.latest(in: catalog, current: current).map { [$0] } ?? []
    }

    /// The sheet closed: this version's highlights have been seen.
    func dismiss() {
        presented = nil
        guard !pending.isEmpty else { return }
        pending = []
        defaults.set(current.description, forKey: Self.lastSeenKey)
    }
}
