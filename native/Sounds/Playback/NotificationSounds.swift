import Foundation
import Observation
import os

#if os(macOS)
import AppKit
#endif

/// Native's notification sounds: what to play, when, and playing it. `SoundsPlugin` calls `play`
/// for session events; other features call it for their own moments (a usage limit reached).
/// Every sound goes through `play`, so the master switch, the triggers, Focus and the timing apply
/// to all of them in one place. (Notifications follow Focus on their own, through the system.)
@Observable
final class NotificationSounds {
    static let shared = NotificationSounds()

    let preferences: SoundPreferences
    let focus: any FocusStatusProviding
    private(set) var catalog: SoundCatalog
    /// Whether a session is on screen. The app sets this; until it does, no session counts as
    /// viewed and `.unlessViewing` behaves like `.always`.
    @ObservationIgnored var isViewing: (SessionContext) -> Bool = { _ in false }
    /// Whether a session will send its failed turn again on its own (a dropped connection). The
    /// app sets this; such a failure isn't worth a sound until Native gives up.
    @ObservationIgnored var isRetrying: (SessionContext) -> Bool = { _ in false }

    @ObservationIgnored private let isAppActive: @MainActor () -> Bool
    @ObservationIgnored private let player = SoundPlayer()
    @ObservationIgnored private var lastPlayed: (date: Date, trigger: SoundTrigger)?
    /// What played and why something didn't, for "why didn't it chime?" (`log stream --predicate
    /// 'subsystem == "Native" AND category == "Sounds"' --info`).
    @ObservationIgnored private let logger = Logger(subsystem: "Native", category: "Sounds")
    /// Several sessions often finish together; one sound says so. Within it, only news more urgent
    /// than what just played gets through (a turn ending into a blocked goal sounds as "needs you").
    private static let burstInterval: TimeInterval = 1.5

    init(
        preferences: SoundPreferences = SoundPreferences(),
        focus: any FocusStatusProviding = SystemFocusStatus(),
        isAppActive: @escaping @MainActor () -> Bool = NotificationSounds.isAppActive
    ) {
        self.preferences = preferences
        self.focus = focus
        self.isAppActive = isAppActive
        catalog = SoundCatalog(customSounds: preferences.customSounds, folder: preferences.soundsFolder)
        if preferences.isEnabled {
            let chimes = SoundTrigger.allCases.compactMap { trigger -> NativeChime? in
                if case .native(let chime) = preferences.sound(for: trigger) { chime } else { nil }
            }
            Task { [player] in
                for chime in Set(chimes) {
                    await player.prepare(chime)
                }
            }
        }
    }

    /// The sound `trigger` plays, falling back to its default when the chosen file has gone missing.
    func option(for trigger: SoundTrigger) -> SoundOption? {
        catalog.option(for: preferences.sound(for: trigger)) ?? catalog.option(for: trigger.defaultSound)
    }

    /// Plays the selected sound for `trigger` if the user wants one for it right now. Returns
    /// whether it played.
    @discardableResult
    func play(_ trigger: SoundTrigger, for session: SessionContext? = nil) async -> Bool {
        guard preferences.isEnabled, preferences.isEnabled(trigger) else { return false }
        if preferences.staysQuietDuringFocus {
            // The first sound that would play is when Native asks to see Focus, never at launch.
            await focus.requestAccessIfNeeded()
            if focus.isFocused == true {
                logger.info("Quiet for \(trigger.rawValue, privacy: .public): a Focus is on")
                return false
            }
        }
        let isViewingSession = session.map(isViewing) ?? false
        guard preferences.timing.allows(isAppActive: isAppActive(), isViewingSession: isViewingSession) else {
            logger.info(
                "Quiet for \(trigger.rawValue, privacy: .public): \(self.preferences.timing.rawValue, privacy: .public)"
            )
            return false
        }
        if let lastPlayed, Date.now.timeIntervalSince(lastPlayed.date) < Self.burstInterval,
            trigger.urgency <= lastPlayed.trigger.urgency
        {
            return false
        }
        guard let option = option(for: trigger) else { return false }
        lastPlayed = (.now, trigger)
        logger.info("Playing \(option.title, privacy: .public) for \(trigger.rawValue, privacy: .public)")
        await player.play(option, volume: preferences.volume)
        return true
    }

    /// Plays a trigger's sound regardless of switches, Focus and timing, for trying it out.
    func preview(_ trigger: SoundTrigger) {
        guard let option = option(for: trigger) else { return }
        Task { await player.play(option, volume: preferences.volume) }
    }

    /// Gives `trigger` a sound, and plays it so the user hears what they picked.
    func select(_ id: SoundID, for trigger: SoundTrigger) {
        preferences.setSound(id, for: trigger)
        preview(trigger)
    }

    /// Turning "Stay quiet during Focus" on is the other moment Native asks to see Focus.
    func setStaysQuietDuringFocus(_ isOn: Bool) {
        preferences.staysQuietDuringFocus = isOn
        if isOn {
            Task { await focus.requestAccessIfNeeded() }
        }
    }

    /// Adds audio files the user picked, gives the last of them to `trigger` and plays it.
    func addSounds(at urls: [URL], for trigger: SoundTrigger) {
        let added = preferences.addCustomSounds(at: urls)
        reloadCatalog()
        if let last = added.last {
            select(.custom(last.id), for: trigger)
        }
    }

    func removeSound(_ id: UUID) {
        preferences.removeCustomSound(id)
        reloadCatalog()
    }

    /// Offers the audio files in `url`, or stops offering a folder's files for nil. A trigger that
    /// played a file the new folder doesn't have goes back to its own default, so its picker never
    /// shows a sound that isn't on its list.
    func setSoundsFolder(_ url: URL?) {
        preferences.soundsFolder = url.map(SoundsFolder.init(url:))
        reloadCatalog()
        for trigger in SoundTrigger.allCases {
            let sound = preferences.sound(for: trigger)
            if case .folder = sound, catalog.option(for: sound) == nil {
                preferences.setSound(trigger.defaultSound, for: trigger)
            }
        }
    }

    /// Lists the sounds folder and the custom files again, for when they've changed or moved.
    func reloadCatalog() {
        catalog = SoundCatalog(customSounds: preferences.customSounds, folder: preferences.soundsFolder)
    }

    static func isAppActive() -> Bool {
        #if os(macOS)
        NSApplication.shared.isActive
        #else
        true
        #endif
    }
}
