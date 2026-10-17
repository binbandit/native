import AppKit
import Foundation
import Observation

/// Native's notification sounds: what to play, when, and playing it. `SoundsPlugin` calls `play`
/// for session events; other features call it for their own moments (a usage limit reached).
@Observable
final class NotificationSounds {
    static let shared = NotificationSounds()

    let preferences: SoundPreferences
    private(set) var catalog: SoundCatalog
    /// Whether a session is on screen. The app sets this; until it does, no session counts as
    /// viewed and `.unlessViewing` behaves like `.always`.
    @ObservationIgnored var isViewing: (SessionContext) -> Bool = { _ in false }

    @ObservationIgnored private let player = SoundPlayer()
    @ObservationIgnored private var lastPlayed = Date.distantPast
    /// Several sessions often finish together; one sound says so.
    private static let burstInterval: TimeInterval = 1.5

    init(preferences: SoundPreferences = SoundPreferences()) {
        self.preferences = preferences
        catalog = SoundCatalog(customSounds: preferences.customSounds)
        if case .native(let chime) = preferences.selection {
            Task { [player] in await player.prepare(chime) }
        }
    }

    /// The selected sound, falling back to the default when its file has gone missing.
    var selectedOption: SoundOption? {
        let selection = preferences.selection
        guard selection != .none else { return nil }
        return catalog.option(for: selection) ?? catalog.option(for: .default)
    }

    /// Plays the selected sound for `trigger` if the user wants one for it right now.
    func play(_ trigger: SoundTrigger, for session: SessionContext? = nil) {
        guard preferences.isEnabled(trigger) else { return }
        let isViewingSession = session.map(isViewing) ?? false
        guard preferences.timing.allows(isAppActive: NSApplication.shared.isActive, isViewingSession: isViewingSession) else { return }
        guard Date.now.timeIntervalSince(lastPlayed) >= Self.burstInterval, let option = selectedOption else { return }
        lastPlayed = .now
        Task { await player.play(option, volume: preferences.volume) }
    }

    /// Plays a sound regardless of triggers and timing, for trying it out.
    func preview(_ id: SoundID? = nil) {
        guard let option = id.map(catalog.option(for:)) ?? selectedOption else { return }
        Task { await player.play(option, volume: preferences.volume) }
    }

    func select(_ id: SoundID) {
        preferences.selection = id
        preview(id)
    }

    /// Adds audio files the user picked, selects the last of them and plays it.
    func addSounds(at urls: [URL]) {
        let added = preferences.addCustomSounds(at: urls)
        reloadCatalog()
        if let last = added.last {
            select(.custom(last.id))
        }
    }

    func removeSound(_ id: UUID) {
        preferences.removeCustomSound(id)
        reloadCatalog()
    }

    /// Looks for Conductor's sounds and the custom files again, for when they've moved.
    func reloadCatalog() {
        catalog = SoundCatalog(customSounds: preferences.customSounds)
    }
}
